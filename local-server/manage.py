"""Explicit local lifecycle and recovery commands. Never runs on a schedule."""
from pathlib import Path
import argparse
import base64
import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from xml.sax.saxutils import escape
from bootstrap import ROOT, SOURCE, LOCAL, SERVER, MYSQL, SCHEMAS, SNAPSHOT_COUNTS_SQL, HIDDEN, mysql, port_open


def credentials():
    return json.loads((LOCAL / "secrets.json").read_text())


def command(text):
    secret = credentials()
    body = ('<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="urn:TC">'
            '<SOAP-ENV:Body><ns1:executeCommand><command>' + escape(text) +
            '</command></ns1:executeCommand></SOAP-ENV:Body></SOAP-ENV:Envelope>').encode()
    basic = base64.b64encode((secret["admin_user"] + ":" + secret["admin_password"]).encode()).decode()
    request = urllib.request.Request("http://127.0.0.1:7878/", body,
                                     {"Content-Type": "text/xml; charset=utf-8", "Authorization": "Basic " + basic, "SOAPAction": "urn:TC#executeCommand"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode()


def process_image(pid):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return None
    try:
        status = wintypes.DWORD()
        if kernel.GetExitCodeProcess(handle, ctypes.byref(status)) and status.value != 259: # STILL_ACTIVE
            return None
        buffer = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(buffer))
        if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
            error = ctypes.get_last_error()
            # A graceful shutdown can finish between OpenProcess and the image query (WinError 31).
            if kernel.GetExitCodeProcess(handle, ctypes.byref(status)) and status.value != 259:
                return None
            raise ctypes.WinError(error)
        return Path(buffer.value).resolve()
    finally:
        kernel.CloseHandle(handle)


def running(name):
    record = LOCAL / f"{name}.pid"
    if not record.exists():
        return None
    pid = int(record.read_text().strip())
    image = process_image(pid)
    if image is None:
        return None
    if image != (SERVER / f"{name}.exe").resolve():
        raise RuntimeError(f"PID {pid} belongs to another executable; refusing to touch it.")
    return pid


def wait_exit(name, timeout=180):
    deadline = time.monotonic() + timeout
    while running(name):
        if time.monotonic() > deadline:
            raise RuntimeError(f"{name} did not stop cleanly; refusing to force stop or back up.")
        time.sleep(1)


def start_database():
    if not port_open(3317):
        database_process = subprocess.Popen([str(MYSQL / "bin/mysqld.exe"), f"--defaults-file={LOCAL / 'my.ini'}"], creationflags=HIDDEN,
                                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(120):
            if database_process.poll() is not None:
                raise RuntimeError("MySQL stopped before becoming ready; inspect local/mysql-error.log.")
            if port_open(3317):
                try:
                    mysql("SELECT 1;")
                    break
                except subprocess.CalledProcessError:
                    pass
            time.sleep(1)
        else:
            raise RuntimeError("MySQL did not become ready within two minutes; inspect local/mysql-error.log.")
    mysql("SELECT 1;")


def start(world_only=False):
    if not world_only and not (LOCAL / "certs/chain.pem").exists():
        raise RuntimeError("Run Certificates.ps1 first.")
    if not world_only and (LOCAL / "certs/profile.json").exists():
        from certificates import validate
        validate(LOCAL / "certs")
    if not world_only:
        try:
            portal = socket.gethostbyname("trinity.actual.battle.net")
        except OSError:
            portal = None
        if portal != "127.0.0.1":
            raise RuntimeError("The local portal mapping is pending. Resolve the connection preference first; start-world is available for independent diagnostics.")
    start_database()
    for name in (["worldserver"] if world_only else ["bnetserver", "worldserver"]):
        if running(name):
            continue
        log = SERVER / "logs" / f"{name}-console.log"
        with log.open("ab") as output:
            proc = subprocess.Popen([str(SERVER / f"{name}.exe"), "-c", str(SERVER / f"{name}.conf")], cwd=SERVER,
                                    creationflags=HIDDEN, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
        (LOCAL / f"{name}.pid").write_text(str(proc.pid))
        print(f"Started {name}, PID {proc.pid}. Startup and migrations are in {log}.", flush=True)


def stop_world():
    if running("worldserver"):
        command("server shutdown 0")
        wait_exit("worldserver")
    pid = running("bnetserver")
    if pid:
        # Login server holds no character state; terminate only this verified executable, after the world saves.
        subprocess.run(["taskkill", "/PID", str(pid), "/F"], check=True, capture_output=True, creationflags=HIDDEN)
        wait_exit("bnetserver", 30)


def stop():
    stop_world()
    if port_open(3317):
        pid_file = LOCAL / "mysql.pid"
        database_pid = int(pid_file.read_text().strip()) if pid_file.exists() else None
        if database_pid:
            image = process_image(database_pid)
            if image and image != (MYSQL / "bin/mysqld.exe").resolve():
                raise RuntimeError("MySQL PID belongs to another executable; refusing to stop it.")
        subprocess.run([str(MYSQL / "bin/mysqladmin.exe"), f"--defaults-extra-file={LOCAL / 'mysql-client.ini'}", "shutdown"],
                       check=True, creationflags=HIDDEN)
        deadline = time.monotonic() + 180
        # mysqladmin returns before InnoDB finishes releasing its files on Windows. Waiting only for
        # the TCP listener can race the final flush and make the next start fail to open ibdata1.
        while (database_pid and process_image(database_pid) is not None) or port_open(3317):
            if time.monotonic() > deadline:
                raise RuntimeError("MySQL has not finished its clean shutdown; refusing to force stop it.")
            time.sleep(1)
    print("Server stopped cleanly.")


def backup():
    stop_world()
    start_database() # A stopped or broken game server must not block backup/rollback.
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    dest = ROOT / "backups" / stamp
    dest.mkdir(parents=True)
    shutil.copytree(LOCAL, dest / "local", ignore=shutil.ignore_patterns("mysql-data", "restore-check-*", "*.pid", "*.log", "ca.key"))
    config = dest / "server"
    config.mkdir()
    for path in SERVER.glob("*.conf"):
        shutil.copy2(path, config / path.name)
    shutil.copytree(SERVER / "worldserver.conf.d", config / "worldserver.conf.d")
    for path in SERVER.glob("*.exe"):
        if path.name in ["worldserver.exe", "bnetserver.exe"]:
            shutil.copy2(path, config / path.name)
    for path in SERVER.glob("*.dll"):
        shutil.copy2(path, config / path.name)
    if (SERVER / "build-manifest.json").exists():
        shutil.copy2(SERVER / "build-manifest.json", dest / "build-manifest.json")
    else:
        raise RuntimeError("No installed build manifest; a recoverable backup requires matching binaries and source revision.")
    if (SERVER / "data-manifest.json").exists():
        shutil.copy2(SERVER / "data-manifest.json", dest / "data-manifest.json")
    commit = subprocess.check_output(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], text=True).strip()
    (dest / "checkout-commit.txt").write_text(commit)
    counts = mysql("SELECT table_schema,COUNT(*) FROM information_schema.tables WHERE table_schema IN ("
                   + ",".join("'" + name + "'" for name in SCHEMAS) + ") GROUP BY table_schema ORDER BY table_schema;")
    (dest / "table-counts.txt").write_text(counts)
    (dest / "row-counts.txt").write_text(mysql(SNAPSHOT_COUNTS_SQL))
    dump = dest / "databases.sql"
    with dump.open("wb") as stream:
        subprocess.run([str(MYSQL / "bin/mysqldump.exe"), f"--defaults-extra-file={LOCAL / 'mysql-client.ini'}",
                        "--single-transaction", "--routines", "--triggers", "--events", "--hex-blob", "--no-tablespaces",
                        "--set-gtid-purged=OFF", "--add-drop-database", "--databases", *SCHEMAS], stdout=stream, check=True, creationflags=HIDDEN)
    with dump.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    (dest / "databases.sha256").write_text(digest)
    (dest / "COMPLETE").write_text(stamp)
    print(f"Backup complete: {dest}")
    return dest


def restore(path, confirmed):
    if not confirmed:
        raise RuntimeError("Restore replaces all five local databases. Supply --confirm-replace after reviewing the backup.")
    path = path.resolve(strict=True)
    if not (path / "COMPLETE").exists():
        raise RuntimeError("Backup has no COMPLETE marker.")
    # Transport identity is independent of the character/database snapshot. Preserve the
    # current one-leaf authority instead of reviving an old, retained CA key from a backup.
    hardened_tls = (LOCAL / "certs/profile.json").exists()
    if hardened_tls:
        from certificates import validate
        validate(LOCAL / "certs")
    with (path / "databases.sql").open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != (path / "databases.sha256").read_text().strip():
        raise RuntimeError("Backup checksum failed.")
    if (path / "data-manifest.json").exists():
        saved_data = json.loads((path / "data-manifest.json").read_text(encoding="utf-8-sig"))
        current_data_file = SERVER / "data-manifest.json"
        current_data = json.loads(current_data_file.read_text(encoding="utf-8-sig")) if current_data_file.exists() else {}
        if saved_data.get("clientVersion") != current_data.get("clientVersion"):
            raise RuntimeError("Backup and current extracted client versions differ. Preserve/restore matching client data before database rollback.")
    # Prepare the matching migration source before replacing any database. Never reset the customization branch.
    manifest = json.loads((path / "build-manifest.json").read_text(encoding="utf-8-sig"))
    revision = manifest["commit"]
    import re
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise RuntimeError("Backup source revision is invalid.")
    rollback_source = ROOT / "rollback" / (revision[:12] + "-" + str(int(time.time())))
    rollback_source.parent.mkdir(exist_ok=True)
    subprocess.run(["git", "-C", str(SOURCE), "worktree", "add", "--detach", str(rollback_source), revision], check=True)
    # Keep a recovery point of the current state before changing anything.
    safety = backup()
    current = credentials()
    old = json.loads((path / "local/secrets.json").read_text())
    mysql(file=path / "databases.sql")
    from configure import ACCEPTED_BUILDS, ensure_accepted_builds
    registered_builds = set(map(int, mysql("SELECT build FROM build_info;", "ff_auth").splitlines()))
    restored_defaults = tuple(build for build in ACCEPTED_BUILDS if build in registered_builds)
    requested_builds = set(ACCEPTED_BUILDS)
    mysql(f"ALTER USER 'forever_local'@'127.0.0.1' IDENTIFIED BY '{old['mysql_server']}';")
    for name in ["worldserver.conf", "bnetserver.conf", "worldserver.exe", "bnetserver.exe"]:
        shutil.copy2(path / "server" / name, SERVER / name)
    for dll in (path / "server").glob("*.dll"):
        shutil.copy2(dll, SERVER / dll.name)
    active_extra = SERVER / "worldserver.conf.d"
    if active_extra.resolve().parent != SERVER.resolve():
        raise RuntimeError("Config directory resolves outside this installation.")
    active_extra.rename(SERVER / f"worldserver.conf.d-before-restore-{int(time.time())}")
    shutil.copytree(path / "server/worldserver.conf.d", active_extra)
    # The instance's root credential is not part of the five application schemas and must remain current.
    old["mysql_root"] = current["mysql_root"]
    (LOCAL / "secrets.json").write_text(json.dumps(old, indent=2))
    if hardened_tls:
        print("Preserved the current one-leaf TLS identity; legacy backup CA keys were not restored.")
    else:
        shutil.copytree(path / "local/certs", LOCAL / "certs", dirs_exist_ok=True)
    if (path / "build-manifest.json").exists():
        shutil.copy2(path / "build-manifest.json", SERVER / "build-manifest.json")
    for name in ["worldserver.conf", "bnetserver.conf"]:
        target = SERVER / name
        text = target.read_text(encoding="utf-8-sig")
        text = re.sub(r'^\s*SourceDirectory\s*=.*$', lambda _: 'SourceDirectory = "' + rollback_source.as_posix() + '"', text, flags=re.M)
        target.write_text(text, encoding="utf-8")
        requested_builds.update(ensure_accepted_builds(target, restored_defaults))
    for build in sorted(requested_builds - registered_builds):
        print(f"Warning: restored ff_auth.build_info has no row for build {build}. "
              f"Clients on that build need a compatible auth row and Realm.AlsoAcceptBuilds in both configs.", file=sys.stderr)
    print(f"Restored matching databases, binaries, credentials and configuration. Safety backup: {safety}")
    print(f"Migration source pinned to {rollback_source}. Start and check the server before playing.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["start", "start-world", "stop", "status", "backup", "restore", "command", "create-account", "check"])
    parser.add_argument("argument", nargs="?")
    parser.add_argument("--confirm-replace", action="store_true")
    args = parser.parse_args()
    if args.action == "start": start()
    elif args.action == "start-world": start(world_only=True)
    elif args.action == "stop": stop()
    elif args.action == "backup": backup()
    elif args.action == "restore": restore(Path(args.argument), args.confirm_replace)
    elif args.action == "command": print(command(args.argument))
    elif args.action == "status":
        print(json.dumps({"bnetserver": running("bnetserver"), "worldserver": running("worldserver"),
                          "mysql3317": port_open(3317), "login1119": port_open(1119), "world8085": port_open(8085)}))
    elif args.action == "check":
        print(command("server info"))
        for port in [1119, 8081, 8085, 7878]:
            if not port_open(port): raise RuntimeError(f"Port {port} is not listening")
        print("Server info and listener checks passed; in-game checks remain separate.")
    elif args.action == "create-account":
        secret = credentials()
        email = secret["game_email"]
        if mysql(f"SELECT COUNT(*) FROM battlenet_accounts WHERE email='{email}';", "ff_auth") != "0":
            raise RuntimeError("The local game account already exists; preserving its password.")
        command(f"bnetaccount create {email} {secret['game_password']}")
        if mysql(f"SELECT COUNT(*) FROM battlenet_accounts WHERE email='{email}';", "ff_auth") != "1":
            raise RuntimeError("The server did not create the local game account.")
        print("Normal local player account created. Owned-bot commands need no GM in this revision. Login details are in local/secrets.json.")


if __name__ == "__main__":
    main()
