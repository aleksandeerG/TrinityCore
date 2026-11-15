"""Render machine-local configs once; preserve existing configs on subsequent runs."""
from pathlib import Path
import json
import re
import shutil
from bootstrap import ROOT, SOURCE, LOCAL, SERVER


def render(template, target, values):
    if target.exists():
        print(f"Preserving {target.name}")
        return
    text = template.read_text(encoding="utf-8-sig")
    for key, value in values.items():
        pattern = r"^\s*" + re.escape(key) + r"\s*=.*$"
        line = f"{key} = {value}"
        if re.search(pattern, text, flags=re.M):
            text = re.sub(pattern, lambda _: line, text, flags=re.M)
        else:
            text += "\n" + line + "\n"
    target.write_text(text, encoding="utf-8")


def main():
    credentials = json.loads((LOCAL / "secrets.json").read_text())
    (SERVER / "logs").mkdir(exist_ok=True)
    extra = SERVER / "worldserver.conf.d"
    extra.mkdir(exist_ok=True)
    quote = lambda path: '"' + path.as_posix() + '"'
    connection = lambda name: f'"127.0.0.1;3317;forever_local;{credentials["mysql_server"]};{name}"'
    common = {"LoginDatabaseInfo": connection("ff_auth"), "BindIP": '"127.0.0.1"', "LogsDir": quote(SERVER / "logs"),
              "Realm.AlsoAcceptBuilds": '"70938,70888,70862"',
              "MySQLExecutable": quote(ROOT / "dependencies/mysql/mysql-8.4.7-winx64/bin/mysql.exe"),
              "SourceDirectory": quote(SOURCE)}
    render(SOURCE / "src/server/worldserver/worldserver.conf.dist", SERVER / "worldserver.conf", {
        **common, "WorldDatabaseInfo": connection("ff_world"), "CharacterDatabaseInfo": connection("ff_characters"),
        "HotfixDatabaseInfo": connection("ff_hotfixes"), "RealmID": 70, "Expansion": 0,
        "DataDir": quote(SERVER), "Updates.EnableDatabases": 15, "Network.SkipBuildAuthKeyCheck": 1,
        "Network.EnterEncryptedModeRegionGroup": 8, "Realm.AlsoAcceptBuilds": '"70938,70888,70862"',
        "Console.Enable": 0, "Ra.Enable": 0, "SOAP.Enabled": 1, "SOAP.IP": '"127.0.0.1"',
        "SOAP.Port": 7878, "PidFile": quote(LOCAL / "worldserver.pid"), "GM.LoginState": 0,
    })
    render(SOURCE / "src/server/bnetserver/bnetserver.conf.dist", SERVER / "bnetserver.conf", {
        **common, "Realm.CfgContentSetID": 137, "Updates.EnableDatabases": 1,
        "LoginREST.ExternalAddress": '"trinity.actual.battle.net"', "LoginREST.LocalAddress": '"trinity.actual.battle.net"',
        "CertificatesFile": quote(LOCAL / "certs/chain.pem"), "PrivateKeyFile": quote(LOCAL / "certs/server.key"),
        "PidFile": quote(LOCAL / "bnetserver.pid"),
    })
    for origin, target in [
        (SOURCE / "src/modules/PlayerbotV2/conf/playerbot.conf.dist", extra / "playerbot.conf"),
        (SOURCE / "local-server/local.conf.template", extra / "zzzz-aleksanderG.conf"),
    ]:
        if not target.exists():
            shutil.copy2(origin, target)
    # These configs contain database passwords. Restrict access with the same owner ACL as local/.
    print("Configuration rendered. server/ and local/ must remain private and outside Git.")


if __name__ == "__main__":
    main()
