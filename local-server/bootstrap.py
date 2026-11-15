"""Initialize this workspace only; refuse to import over nonempty databases.

Run from a normal PowerShell as the owner: python source/local-server/bootstrap.py
Secrets and mutable state are outside the Git checkout.
"""
from pathlib import Path
import hashlib
import json
import secrets
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source"
LOCAL = ROOT / "local"
SERVER = ROOT / "server"
MYSQL = ROOT / "dependencies/mysql/mysql-8.4.7-winx64"
SCHEMAS = ["ff_auth", "ff_characters", "ff_world", "ff_hotfixes", "playerbot"]
SNAPSHOT_COUNTS_SQL = " UNION ALL ".join(
    f"SELECT '{table}',COUNT(*) FROM {table}" for table in
    ["ff_auth.account", "ff_auth.battlenet_accounts", "ff_auth.realmlist", "ff_characters.characters", "playerbot.playerbots_names"]
) + " ORDER BY 1;"
HIDDEN = subprocess.CREATE_NO_WINDOW


def write(path, text):
    path.write_text(text, encoding="utf-8")


def mysql(sql=None, database=None, file=None):
    args = [str(MYSQL / "bin/mysql.exe"), f"--defaults-extra-file={LOCAL / 'mysql-client.ini'}", "--binary-mode", "--batch", "--skip-column-names"]
    if database:
        args.append(database)
    if file:
        with open(file, "rb") as stream:
            return subprocess.run(args, stdin=stream, check=True, creationflags=HIDDEN)
    return subprocess.run(args, input=sql, text=True, capture_output=True, check=True, creationflags=HIDDEN).stdout.strip()


def port_open(port):
    with socket.socket() as sock:
        sock.settimeout(0.5)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def main():
    LOCAL.mkdir(exist_ok=True)
    SERVER.mkdir(exist_ok=True)
    private = LOCAL / "secrets.json"
    data = LOCAL / "mysql-data"
    if not private.exists():
        if data.exists():
            raise RuntimeError("Existing MySQL data without credentials: inspect it manually; never reinitialize.")
        credentials = {"mysql_root": secrets.token_hex(24), "mysql_server": secrets.token_hex(24),
                       "admin_user": "FFADMIN", "admin_password": secrets.token_hex(8).upper(),
                       "game_email": "aleksander@forever.local", "game_password": secrets.token_hex(8).upper()}
        write(private, json.dumps(credentials, indent=2))
    credentials = json.loads(private.read_text())
    ini = LOCAL / "my.ini"
    write(ini, f'''[mysqld]
basedir="{MYSQL.as_posix()}"
datadir="{data.as_posix()}"
port=3317
bind-address=127.0.0.1
mysqlx=OFF
skip-log-bin
max_allowed_packet=128M
innodb_buffer_pool_size=1G
character-set-server=utf8mb4
log-error="{(LOCAL / 'mysql-error.log').as_posix()}"
pid-file="{(LOCAL / 'mysql.pid').as_posix()}"
''')
    write(LOCAL / "mysql-client.ini", f'''[client]
host=127.0.0.1
port=3317
protocol=tcp
user=root
password={credentials['mysql_root']}
default-character-set=utf8mb4
''')
    init = LOCAL / "mysql-init.sql"
    if not data.exists():
        subprocess.run([str(MYSQL / "bin/mysqld.exe"), f"--defaults-file={ini}", "--initialize-insecure"], check=True, creationflags=HIDDEN)
        statements = [f"ALTER USER 'root'@'localhost' IDENTIFIED BY '{credentials['mysql_root']}';",
                      f"CREATE USER 'forever_local'@'127.0.0.1' IDENTIFIED BY '{credentials['mysql_server']}';"]
        for name in SCHEMAS:
            statements += [f"CREATE DATABASE `{name}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;",
                           f"GRANT ALL PRIVILEGES ON `{name}`.* TO 'forever_local'@'127.0.0.1';"]
        write(init, "\n".join(statements))
    if not port_open(3317):
        args = [str(MYSQL / "bin/mysqld.exe"), f"--defaults-file={ini}"]
        if init.exists():
            args.append(f"--init-file={init}")
        subprocess.Popen(args, creationflags=HIDDEN, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(120):
            if port_open(3317):
                break
            time.sleep(1)
        else:
            raise RuntimeError("MySQL failed to start. Inspect local/mysql-error.log")
    mysql("SELECT 1;")  # verify our credentials; never use an unknown server at this port
    if init.exists():
        init.unlink()
    imports = [
        ("ff_auth", SOURCE / "sql/base/auth_database.sql"),
        ("ff_characters", SOURCE / "sql/base/characters_database.sql"),
        ("ff_world", SERVER / "TDB_full_world_forever_2026_10_14.sql"),
        ("ff_hotfixes", SERVER / "TDB_full_hotfixes_forever_2026_10_14.sql"),
        ("playerbot", SOURCE / "sql/playerbot_shared/playerbot_shared_schema.sql"),
    ]
    for name, path in imports:
        marker = LOCAL / f"import-{name}.done"
        if marker.exists():
            continue
        count = int(mysql(f"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='{name}';"))
        if count:
            raise RuntimeError(f"{name} contains {count} tables without an import marker. Inspect before importing.")
        print(f"Importing {name} from {path.name}", flush=True)
        mysql(database=name, file=path)
        if name == "playerbot":
            mysql(database=name, file=SOURCE / "sql/playerbot_shared/playerbot_shared_data.sql")
        write(marker, str(path))

    # Bootstrap a loopback-only console account, using this core's GruntSRP6 registration algorithm.
    # The actual game account is created later through the server's native bnetaccount command.
    if mysql("SELECT COUNT(*) FROM account WHERE username='FFADMIN';", "ff_auth") == "0":
        salt = secrets.token_bytes(32)
        digest = hashlib.sha1((credentials["admin_user"] + ":" + credentials["admin_password"]).encode()).digest()
        x = int.from_bytes(hashlib.sha1(salt + digest).digest(), "little")
        modulus = int("894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7", 16)
        verifier = pow(7, x, modulus).to_bytes(32, "little")
        mysql(f"INSERT INTO account(username,salt,verifier) VALUES('FFADMIN',UNHEX('{salt.hex()}'),UNHEX('{verifier.hex()}'));"
              "INSERT INTO account_access(AccountID,SecurityLevel,RealmID) SELECT id,3,-1 FROM account WHERE username='FFADMIN';", "ff_auth")
    print("Database initialization complete. Credentials are in local/secrets.json; do not commit them.", flush=True)


if __name__ == "__main__":
    main()
