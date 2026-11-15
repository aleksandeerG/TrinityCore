"""Security regressions use disposable test authorities, never the installed CA."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa

import certificates as certs

OPENSSL = Path("C:/Program Files/Git/usr/bin/openssl.exe")


class CertificateTests(unittest.TestCase):
    def test_profile_key_identity_and_tampering(self):
        with tempfile.TemporaryDirectory(prefix="forever-cert-test-") as temporary:
            folder = Path(temporary)
            metadata = certs.issue(folder)
            self.assertFalse((folder / "ca.key").exists())
            self.assertFalse(metadata["caPrivateKeyPersisted"])
            self.assertGreater(datetime.fromisoformat(metadata["serverExpiresUtc"]),
                               datetime.now(timezone.utc) + timedelta(days=1824))
            self.assertEqual(certs.validate(folder), metadata)
            result = subprocess.run([str(OPENSSL), "verify", "-CAfile", str(folder / "ca.pem"),
                                     "-purpose", "sslserver", "-verify_hostname", certs.HOST,
                                     str(folder / "server.pem")], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            (folder / "ca.key").write_text("retained key sentinel")
            with self.assertRaises(RuntimeError):
                certs.validate(folder)
            (folder / "ca.key").unlink()
            metadata["caSha256"] = "00"
            (folder / "profile.json").write_text(json.dumps(metadata))
            with self.assertRaises(RuntimeError):
                certs.validate(folder)

    def test_dns_constraints_and_purposes(self):
        # Mint hostile leaves with an unrelated throwaway CA using the same constraint builder.
        # This does not create additional certificates under the production authority.
        now = datetime.now(timezone.utc)
        ca_key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        leaf_key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        ca = certs.ca_builder(ca_key, now, now + timedelta(days=2)).sign(ca_key, hashes.SHA256())
        with tempfile.TemporaryDirectory(prefix="forever-constraint-test-") as temporary:
            folder = Path(temporary)
            (folder / "ca.pem").write_bytes(ca.public_bytes(serialization.Encoding.PEM))
            for host, expected_error in ((certs.HOST, None), ("sub." + certs.HOST, "excluded subtree violation"),
                                         ("account.battle.net", "permitted subtree violation"),
                                         ("example.com", "permitted subtree violation")):
                with self.subTest(host=host):
                    leaf = certs.leaf_builder(leaf_key, ca, now, now + timedelta(days=1), host).sign(ca_key, hashes.SHA256())
                    (folder / "leaf.pem").write_bytes(leaf.public_bytes(serialization.Encoding.PEM))
                    args = [str(OPENSSL), "verify", "-CAfile", str(folder / "ca.pem"), "-purpose", "sslserver",
                            "-verify_hostname", host, str(folder / "leaf.pem")]
                    result = subprocess.run(args, capture_output=True, text=True)
                    if expected_error:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(expected_error, result.stderr)
                    else:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        wrong_host = subprocess.run(args[:-3] + ["-verify_hostname", "account.battle.net", args[-1]],
                                                    capture_output=True, text=True)
                        self.assertNotEqual(wrong_host.returncode, 0)
                        self.assertIn("hostname mismatch", wrong_host.stderr)
                        wrong_purpose = subprocess.run([str(OPENSSL), "verify", "-CAfile", str(folder / "ca.pem"),
                                                        "-purpose", "sslclient", str(folder / "leaf.pem")],
                                                       capture_output=True, text=True)
                        self.assertNotEqual(wrong_purpose.returncode, 0)
                        self.assertIn("unsuitable certificate purpose", wrong_purpose.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
