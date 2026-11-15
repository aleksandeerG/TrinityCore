"""Check login startup and TLS using a per-test CA file, without changing Windows trust or hosts.

Diagnostic only: numeric advertised REST addresses are unsuitable for the real game's hostname check.
The normal bnetserver.conf remains unchanged.
"""
import json
import re
import socket
import ssl
import subprocess
import time
from bootstrap import LOCAL, SERVER, HIDDEN, port_open


def main():
    for port in (1119, 8081):
        if port_open(port):
            raise RuntimeError(f"Port {port} is already occupied; refusing to use another login server.")
    config = (SERVER / "bnetserver.conf").read_text(encoding="utf-8-sig")
    for key in ("LoginREST.ExternalAddress", "LoginREST.LocalAddress"):
        config = re.sub(r"^\s*" + re.escape(key) + r"\s*=.*$", key + ' = "127.0.0.1"', config, flags=re.M)
    temporary = LOCAL / "bnetserver-diagnostic.conf"
    temporary.write_text(config, encoding="utf-8")
    log = SERVER / "logs/bnetserver-diagnostic-console.log"
    with log.open("ab") as output:
        process = subprocess.Popen([str(SERVER / "bnetserver.exe"), "-c", str(temporary)], cwd=SERVER, creationflags=HIDDEN,
                                   stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
    try:
        for _ in range(300):
            if process.poll() is not None:
                raise RuntimeError(f"Login server stopped with {process.returncode}; inspect {log}.")
            if port_open(1119) and port_open(8081):
                break
            time.sleep(1)
        else:
            raise RuntimeError("Login server did not start within five minutes")
        listeners = []
        for line in subprocess.check_output(["netstat", "-ano", "-p", "tcp"], text=True, creationflags=HIDDEN).splitlines():
            fields = line.split()
            if len(fields) == 5 and fields[-1] == str(process.pid) and fields[3] == "LISTENING":
                listeners.append(fields[1])
        if not listeners or any(not address.startswith(("127.0.0.1:", "[::1]:")) for address in listeners):
            raise RuntimeError(f"Login server listeners are not verified loopback-only: {listeners}")
        context = ssl.create_default_context(cafile=str(LOCAL / "certs/ca.pem"))
        with socket.create_connection(("127.0.0.1", 8081), timeout=15) as raw:
            with context.wrap_socket(raw, server_hostname="trinity.actual.battle.net") as connection:
                certificate = connection.getpeercert()
                result = {"loginStartup": True, "tlsVerified": True, "protocol": connection.version(),
                          "subjectAltName": certificate.get("subjectAltName"), "windowsTrustChanged": False,
                          "listeners": listeners,
                          "hostsChanged": False, "realClientLoginTested": False}
        (LOCAL / "login-server-diagnostic.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    finally:
        if process.poll() is None:
            process.terminate() # This exact diagnostic process, with no player character state.
        process.wait(timeout=60)


if __name__ == "__main__":
    main()
