"""Restore a backup into a fresh, isolated MySQL on 127.0.0.1:3318. Preserve production data."""
from pathlib import Path
import argparse
import hashlib
import json
import secrets
import subprocess
import time
from bootstrap import ROOT, LOCAL, MYSQL, HIDDEN, SCHEMAS, SNAPSHOT_COUNTS_SQL, port_open


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("backup", type=Path)
    args = parser.parse_args()
    backup = args.backup.resolve(strict=True)
    if not (backup / "COMPLETE").exists():
        raise RuntimeError("Backup is incomplete")
    with (backup / "databases.sql").open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != (backup / "databases.sha256").read_text().strip():
        raise RuntimeError("Backup checksum failed")
    if port_open(3318):
        raise RuntimeError("Port 3318 is occupied; will not use an existing instance")
    test = LOCAL / ("restore-check-" + str(int(time.time())))
    test.mkdir()
    password = secrets.token_hex(24)
    ini = test / "my.ini"
    ini.write_text(f'''[mysqld]
basedir="{MYSQL.as_posix()}"
datadir="{(test / 'data').as_posix()}"
bind-address=127.0.0.1
port=3318
mysqlx=OFF
skip-log-bin
innodb_buffer_pool_size=256M
max_allowed_packet=128M
log-error="{(test / 'mysql.log').as_posix()}"
''')
    client = test / "client.ini"
    client.write_text(f"[client]\nhost=127.0.0.1\nport=3318\nprotocol=tcp\nuser=root\npassword={password}\ndefault-character-set=utf8mb4\n")
    init = test / "init.sql"
    init.write_text(f"ALTER USER 'root'@'localhost' IDENTIFIED BY '{password}';")
    executable = str(MYSQL / "bin/mysqld.exe")
    subprocess.run([executable, f"--defaults-file={ini}", "--initialize-insecure"], check=True, creationflags=HIDDEN)
    process = subprocess.Popen([executable, f"--defaults-file={ini}", f"--init-file={init}"], creationflags=HIDDEN,
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ready = False
    try:
        for _ in range(120):
            if process.poll() is not None:
                raise RuntimeError("Isolated restore instance failed; inspect its log")
            if port_open(3318):
                ready = True
                break
            time.sleep(1)
        if not ready:
            raise RuntimeError("Isolated restore instance did not start")
        command = [str(MYSQL / "bin/mysql.exe"), f"--defaults-extra-file={client}", "--binary-mode", "--batch", "--skip-column-names"]
        with (backup / "databases.sql").open("rb") as stream:
            subprocess.run(command, stdin=stream, check=True, creationflags=HIDDEN)
        query = "SELECT table_schema,COUNT(*) FROM information_schema.tables WHERE table_schema IN (" + ",".join("'" + name + "'" for name in SCHEMAS) + ") GROUP BY table_schema ORDER BY table_schema;"
        restored = subprocess.check_output(command, input=query, text=True, creationflags=HIDDEN).strip()
        if restored != (backup / "table-counts.txt").read_text().strip():
            raise RuntimeError("Restored schema counts differ from backup")
        rows = subprocess.check_output(command, input=SNAPSHOT_COUNTS_SQL, text=True, creationflags=HIDDEN).strip()
        if rows != (backup / "row-counts.txt").read_text().strip():
            raise RuntimeError("Restored account/character/name-pool row counts differ from backup")
        result = {"backup": str(backup), "sha256": digest, "tables": restored, "restored": True,
                  "criticalRows": rows,
                  "testInstance": str(test), "productionDataChanged": False}
        (backup / "restore-check.json").write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
    finally:
        if ready:
            subprocess.run([str(MYSQL / "bin/mysqladmin.exe"), f"--defaults-extra-file={client}", "shutdown"], check=True, creationflags=HIDDEN)
        elif process.poll() is None:
            process.terminate() # Only the new disposable instance; never the production process.
        process.wait(timeout=120)
        if init.exists():
            init.unlink()


if __name__ == "__main__":
    main()
