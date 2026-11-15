"""One-leaf local TLS authority. Its signing key is never serialized or persisted.

Requires Python cryptography >= 42. Only the server's private key is saved.
This avoids an on-disk CA key, not all possible OS memory/pagefile/crash-dump traces.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

HOST = "trinity.actual.battle.net"
PROFILE = "forever-single-leaf-v1"
CERTS = Path(__file__).resolve().parents[2] / "local/certs"


def ca_builder(key, now, expires):
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Forever single-leaf CA " + uuid.uuid4().hex[:12])])
    return (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=5)).not_valid_after(expires)
            .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
            .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), critical=True)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=True)
            .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
            # The permitted subtree includes HOST; exclude its descendants explicitly.
            # Enforcement on trust anchors is verifier-dependent. The signing key is discarded too.
            .add_extension(x509.NameConstraints([x509.DNSName(HOST)], [x509.DNSName("." + HOST)]), critical=True))


def leaf_builder(key, ca, now, expires, hostname=HOST):
    return (x509.CertificateBuilder()
            .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, hostname)]))
            .issuer_name(ca.subject).public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=5)).not_valid_after(expires)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(x509.KeyUsage(True, False, True, False, False, False, False, False, False), critical=True)
            .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]), critical=False)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=True)
            .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(ca.public_key()), critical=False))


def issue(directory):
    now = datetime.now(timezone.utc).replace(microsecond=0)
    try:
        expires = now.replace(year=now.year + 5)
    except ValueError:  # Leap day.
        expires = now.replace(year=now.year + 5, day=28)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=4096)
    server_key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    ca = ca_builder(ca_key, now, expires + timedelta(days=30)).sign(ca_key, hashes.SHA256())
    leaf = leaf_builder(server_key, ca, now, expires).sign(ca_key, hashes.SHA256())
    # Never call private_bytes on ca_key, never export it, never issue another leaf.
    del ca_key
    ca_pem = ca.public_bytes(serialization.Encoding.PEM)
    leaf_pem = leaf.public_bytes(serialization.Encoding.PEM)
    (directory / "ca.pem").write_bytes(ca_pem)
    (directory / "server.pem").write_bytes(leaf_pem)
    (directory / "chain.pem").write_bytes(leaf_pem + ca_pem)
    (directory / "server.key").write_bytes(server_key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    metadata = {"profile": PROFILE, "hostname": HOST, "createdUtc": now.isoformat(),
                "serverExpiresUtc": expires.isoformat(), "caExpiresUtc": ca.not_valid_after_utc.isoformat(),
                "caThumbprint": ca.fingerprint(hashes.SHA1()).hex().upper(),
                "caSha256": ca.fingerprint(hashes.SHA256()).hex(),
                "serverSha256": leaf.fingerprint(hashes.SHA256()).hex(),
                "caPrivateKeyPersisted": False, "issuedLeafCount": 1}
    (directory / "profile.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return validate(directory)


def validate(directory):
    expected = {"ca.pem", "server.pem", "chain.pem", "server.key", "profile.json"}
    if {p.name for p in directory.iterdir()} != expected or any(p.is_symlink() for p in directory.iterdir()):
        raise RuntimeError("Certificate directory is not the one-leaf profile (extra/missing files or a retained CA key).")
    meta = json.loads((directory / "profile.json").read_text(encoding="utf-8"))
    ca = x509.load_pem_x509_certificate((directory / "ca.pem").read_bytes())
    leaf = x509.load_pem_x509_certificate((directory / "server.pem").read_bytes())
    key = serialization.load_pem_private_key((directory / "server.key").read_bytes(), password=None)
    if meta.get("profile") != PROFILE or meta.get("caPrivateKeyPersisted") is not False or meta.get("issuedLeafCount") != 1:
        raise RuntimeError("Missing one-leaf generation provenance; explicitly rotate legacy certificates.")
    ca.verify_directly_issued_by(ca)
    leaf.verify_directly_issued_by(ca)
    if ca.fingerprint(hashes.SHA1()).hex().upper() != meta.get("caThumbprint"):
        raise RuntimeError("CA thumbprint does not match the profile.")
    if ca.fingerprint(hashes.SHA256()).hex() != meta.get("caSha256") or leaf.fingerprint(hashes.SHA256()).hex() != meta.get("serverSha256"):
        raise RuntimeError("Certificate fingerprints do not match the profile.")
    constraints = ca.extensions.get_extension_for_class(x509.NameConstraints)
    if not constraints.critical or constraints.value != x509.NameConstraints([x509.DNSName(HOST)], [x509.DNSName("." + HOST)]):
        raise RuntimeError("CA DNS constraints are not restricted to the local hostname.")
    for cert, is_ca in ((ca, True), (leaf, False)):
        basic = cert.extensions.get_extension_for_class(x509.BasicConstraints)
        usage = cert.extensions.get_extension_for_class(x509.ExtendedKeyUsage)
        key_usage = cert.extensions.get_extension_for_class(x509.KeyUsage)
        expected_key_usage = (x509.KeyUsage(False, False, False, False, False, True, True, False, False) if is_ca else
                              x509.KeyUsage(True, False, True, False, False, False, False, False, False))
        if (not basic.critical or basic.value != x509.BasicConstraints(is_ca, 0 if is_ca else None)
                or not usage.critical or list(usage.value) != [ExtendedKeyUsageOID.SERVER_AUTH]
                or not key_usage.critical or key_usage.value != expected_key_usage):
            raise RuntimeError("Certificate constraints/purposes are incorrect.")
        if not cert.not_valid_before_utc <= datetime.now(timezone.utc) < cert.not_valid_after_utc:
            raise RuntimeError("Certificate is outside its validity period.")
        if not isinstance(cert.public_key(), rsa.RSAPublicKey) or cert.public_key().key_size < 3072:
            raise RuntimeError("Certificate RSA key is smaller than 3072 bits.")
    if list(leaf.extensions.get_extension_for_class(x509.SubjectAlternativeName).value) != [x509.DNSName(HOST)]:
        raise RuntimeError("Server certificate contains an unexpected identity.")
    if key.public_key().public_numbers() != leaf.public_key().public_numbers():
        raise RuntimeError("Server certificate and private key do not match.")
    if ca.public_key().public_numbers() == key.public_key().public_numbers():
        raise RuntimeError("The saved key must not be the CA key.")
    if (directory / "chain.pem").read_bytes() != (directory / "server.pem").read_bytes() + (directory / "ca.pem").read_bytes():
        raise RuntimeError("Server chain order/content is incorrect.")
    if (leaf.not_valid_after_utc > ca.not_valid_after_utc
            or meta.get("serverExpiresUtc") != leaf.not_valid_after_utc.isoformat()
            or meta.get("caExpiresUtc") != ca.not_valid_after_utc.isoformat()):
        raise RuntimeError("Certificate expiration metadata or CA lifetime is inconsistent.")
    return meta


def install(rotate=False):
    if CERTS.is_symlink() or CERTS.parent.is_symlink():
        raise RuntimeError("Refusing redirected certificate paths.")
    if CERTS.exists() and not rotate:
        return validate(CERTS)
    CERTS.parent.mkdir(exist_ok=True)
    stage = CERTS.parent / (".certificates-new-" + uuid.uuid4().hex)
    retired = CERTS.parent / (".certificates-retired-" + uuid.uuid4().hex)
    stage.mkdir()
    try:
        metadata = issue(stage)
        if CERTS.exists():
            # Only replace the managed certificate files, never an unrelated directory.
            managed = {"ca.cnf", "ca.key", "ca.pem", "ca.srl", "chain.pem", "leaf.ext", "server.cnf",
                       "server.csr", "server.key", "server.pem", "profile.json"}
            if any(not p.is_file() or p.is_symlink() or p.name not in managed for p in CERTS.iterdir()):
                raise RuntimeError("Unexpected content in certificate directory; preserved without replacement.")
            CERTS.rename(retired)
        try:
            stage.rename(CERTS)
        except BaseException:
            if retired.exists():
                retired.rename(CERTS)
            raise
        if retired.exists():
            # Checked absolute target within local, containing only managed certificate files.
            if retired.resolve().parent != CERTS.parent.resolve():
                raise RuntimeError("Retired certificate directory escaped local.")
            shutil.rmtree(retired)
        return metadata
    finally:
        if stage.exists() and stage.resolve().parent == CERTS.parent.resolve():
            shutil.rmtree(stage)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rotate", action="store_true", help="Explicitly replace existing certificates; old CA must be untrusted first.")
    parser.add_argument("--check", action="store_true", help="Validate the existing profile without generating anything.")
    args = parser.parse_args()
    if args.check and args.rotate:
        parser.error("--check and --rotate are mutually exclusive")
    print(json.dumps(validate(CERTS) if args.check else install(args.rotate), indent=2))
