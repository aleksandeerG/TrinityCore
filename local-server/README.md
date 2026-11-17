# aleksanderG's local WoW Forever server

Source: https://github.com/aleksandeerG/TrinityCore, branch `aleksanderG`.
Upstream: https://github.com/Karrz1/TrinityCore, branch `forever-bots`.
The clean local `forever-bots` branch tracks `upstream/forever-bots`. Custom commits go on `aleksanderG`.
Never merge upstream `master` or `forever` directly: upstream already merges core fixes into its bot branch
(for example `51b5ae0971`, merging `e6399e4fcb`). No upstream PR is requested.

See [SESSION.md](SESSION.md) for the last verified state and pending work. These are setup scripts and templates;
their presence does not mean startup or gameplay tests have passed.

## Paths and privacy

All commands below run in PowerShell from `F:\Games\World of Warcraft Forever Trinity Core`.

| Path | Purpose |
| --- | --- |
| `source` | Git checkout; only custom source, scripts, templates and docs are pushed |
| `build` | Generated CMake/Ninja build, outside Git |
| `server` | Installed source-built executables, private configs, logs and extracted client data |
| `dependencies` | Portable MySQL and pinned vcpkg packages |
| `local` | Random credentials, CA/private keys, MySQL data, import markers and private state |
| `backups` | Complete database/config/binary recovery points; private, outside Git |
| `inspection` | Downloaded documentation and diagnostic/build logs; outside Git |
| `tools\WoWForeverLauncher.exe` | Verified upstream v0.1.36.1 client launcher |
| `F:\Games\World of Warcraft` | User's completed Forever client; product `wowf`, `_forever_\Wow.exe` |

`local`, `server` and `backups` have owner/SYSTEM/Administrators ACLs. Do not copy them into `source` or publish them.
Keep passwords, private keys, dumps, maps, client files and generated builds out of Git. The CA key is never shared.
No Windows service, boot startup, router mapping or firewall exception is installed. MySQL listens only on
`127.0.0.1:3317` with its X protocol disabled. Game/login servers bind to `127.0.0.1`; RA is off.
SOAP administration uses `127.0.0.1:7878` with a separate random local admin password.

## Reproduce the source build

The installed compiler is Visual Studio 2022 17.13, MSVC 19.43, x64, with CMake 3.30.5 and Ninja.
The source requires C++20, CMake >=3.24, Boost >=1.78 on Windows, OpenSSL >=3 and MySQL >=8.0.34.
This setup uses portable MySQL **8.4.7**, Boost **1.92.0** and OpenSSL **3.6.5**.
vcpkg is pinned to **8f363bdc11359ede4bc51e5eb32a2617538049c8**; Boost uses `x64-windows-static-md`,
OpenSSL uses shared `x64-windows` (static libcrypto collides with the bundled CASC reader's AES symbols).
The exact dependency packages are in `Dependencies.ps1` (a list of CMake components alone omits required headers).

On a fresh checkout, put the official `mysql-8.4.7-winx64.zip` from
https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.7-winx64.zip under `downloads`, and extract into `dependencies\mysql`.
Clone microsoft/vcpkg into `dependencies\vcpkg`, check out the pinned revision, run its `bootstrap-vcpkg.bat -disableMetrics`, then:

```powershell
.\source\local-server\Dependencies.ps1
.\source\local-server\Build.ps1 -Jobs 6
```

The build enables servers, all static scripts, all four extraction tools, Playerbot V2 and tests.
Build.ps1 creates/reuses a short drive alias (normally `W:`) pointing at this exact workspace to avoid Windows'
command-line length limit. It never replaces another mapping or moves files. Remove the alias after build work with
`subst W: /D` if desired; a later build recreates it. Runtime configs use full paths and do not depend on the alias.
It runs `[QuestCollectionLoot]` regressions before installing. Stop the local server before installing another build.
Use `-Fresh` only when deliberately replacing a broken/stale CMake configuration; normal rebuilds are incremental.
`server\build-manifest.json` records the installed source commit. Never replace its executables with a repack update.
Later script/documentation commits do not change the installed C++ revision; the backup records both the running manifest
and current checkout commit. Runtime code customizations must be rebuilt before claiming they are active.

Initial database release: [forever-tdb-2026-10-14](https://github.com/Karrz1/TrinityCore/releases/tag/forever-tdb-2026-10-14).
Extract `TDB_full_world_forever_2026_10_14.sql` and `TDB_full_hotfixes_forever_2026_10_14.sql` into `server`.
`bootstrap.py` creates a separate MySQL instance, generates random passwords, creates schemas `ff_auth`, `ff_characters`,
`ff_world`, `ff_hotfixes`, `playerbot`, and imports the initial schemas and shared bot data. It refuses to import over a
nonempty schema without its completed import marker. Do not delete markers to retry a partially imported database.

```powershell
python .\source\local-server\bootstrap.py
python .\source\local-server\configure.py
```

`configure.py` preserves existing configs. Core/custom SQL applies on startup with `Updates.EnableDatabases = 15`;
the bot migration manager reads `sql/playerbot_v2` through `SourceDirectory`. Never use the module's drift-repair SQL
on a fresh database. Startup logs are the authority for whether all migrations succeeded.

## Client data, certificate and launcher

Client build **70938** appears in the current v0.1.36.1 release manifest and the source auth migration
`2026_11_13_70_auth_classic_70938.sql`. Both configs include it in `Realm.AlsoAcceptBuilds`; realm ID must be 70.
Upstream notes that this build uses the 70790 packet numbering until newer differences are discovered. Acceptance
in a manifest is not proof that every feature works. Recheck before allowing Battle.net to update the client.

Once the client installation is complete and tools are built:

```powershell
.\source\local-server\Extract.ps1 -Threads 6
.\source\local-server\Prepare-Client.ps1
```

Extraction runs mapextractor, vmap4extractor, vmap4assembler, then mmaps_generator against the user's client.
Bots need **mmaps**. The upstream script validates start tiles and supports resuming. Output and temporary extraction
files remain under `server`; no Blizzard assets are committed. Do not run extraction during a Battle.net client update.
The addon installer copies `ForeverBots`, `ForeverDots` and `ForeverCombatNameplates` from this checkout and backs up existing copies in `local`.

The documented real-client connection requires:

1. Exactly `127.0.0.1 trinity.actual.battle.net` in Windows hosts, so that login name reaches this PC.
2. A certificate for that name, trusted by the Windows account running the game.
3. The supported launcher each time; it installs the server public key into the running client, including the newer
   certificate-key mode. Running Wow.exe directly misses that step.

**The user authorized the one-leaf certificate design, and connection setup is installed.** The new CA is trusted
only in the playing user's CurrentUser Root store. The single tagged localhost hosts entry is installed system-wide.
Native Windows TLS 1.3 verified the normal login server and rejected an unrelated hostname. The user subsequently
confirmed real-client world entry in Northshire Valley. Character and accepted-quest saving were verified in the DB;
logout/reconnect, party, dungeon and collection-drop checks remain pending.

Independent diagnostics are possible without those Windows changes: `python .\source\local-server\verify_login_server.py`
uses a separate temporary login config and verifies TLS with an explicit CA file. `Server.ps1 start-world` starts only the
world server for database/startup/account checks once extraction is complete. These do not constitute real-client login.

For manual setup, the existing public CA file is `local\certs\ca.pem`: install it into the playing user's Trusted Root
store and add the exact localhost hosts line as Administrator. The launcher helper also recognizes a manual installation.
The commands below perform the same scoped setup and keep the recorded thumbprint/hosts backup for undo.

```powershell
# Required for certificate generation/validation (already installed on this PC).
python -m pip install -r .\source\local-server\requirements.txt
# Run as the Windows user who plays: reuses the verified one-leaf profile and trusts only CurrentUser Root.
.\source\local-server\Certificates.ps1
# Run this one in an Administrator PowerShell: adds only the tagged localhost name and saves original bytes.
.\source\local-server\Certificates.ps1 -HostsOnly
```

The CA has a critical permitted DNS subtree `trinity.actual.battle.net` and an excluded descendant subtree
`.trinity.actual.battle.net`, plus server-authentication purpose and path-length zero. Root constraints are verifier-dependent;
do not treat them as a universal application security boundary. OpenSSL tests accept the exact name and reject its descendants
and unrelated names. The leaf names only `trinity.actual.battle.net`, cannot act as a CA, and permits server authentication only.

`certificates.py` generates the RSA-4096 CA signing key in memory, issues exactly one RSA-3072 leaf, and never serializes or
writes the CA key. Only `server.key` is saved, protected by the local directory's owner/SYSTEM/Administrators ACLs. This avoids
an on-disk signing-key file; it does not promise protection against OS memory dumps, paging or a compromised machine during
generation. The retired, untrusted live CA/key were removed. Older protected backups still contain the old, untrusted identity;
the new CA signing key is absent from every backup because it was never written. Backup now excludes `ca.key`, and database
restore preserves the currently installed one-leaf TLS identity rather than reviving an older backup's CA key.

Installed leaf validity ends **15 November 2031**; the CA ends **15 December 2031**. `local\certs\profile.json` records exact UTC
times and public fingerprints. Rotation requires a new authority and a new trust installation because no signing key remains.
Remove current trust with `Certificates.ps1 -Undo`, stop the login server, then use `Certificates.ps1 -GenerateOnly -Rotate`
to explicitly generate and validate a fresh five-year identity without installing trust yet. Rerunning the normal setup
validates/reuses the existing profile and never silently rotates it. No certificate-validation bypass is used.

Undo trust with `Certificates.ps1 -Undo` as the playing user. Undo only this installation's tagged hosts line with
`Certificates.ps1 -HostsOnly -Undo` as Administrator. Previous hosts bytes are retained in `local\hosts-before-forever.bin`;
do not overwrite later unrelated hosts edits with that backup.

While the normal login server is running, `verify_windows_tls.ps1` checks Windows user trust, exact localhost resolution,
successful TLS and rejection of an unrelated hostname, without a certificate-validation callback. Its public report is
`local\windows-tls-verification.json`. Security regressions: `python -m unittest discover -s source/local-server -p test_certificates.py -v`.

Launcher: [v0.1.36.1](https://github.com/Karrz1/Karrz-playerbots-wow-forever/releases/tag/v0.1.36.1), verified SHA-256
`6e05740db380c87b6cb5e0bd32da0fce859ed81a675f86e6d560a6ea2549d8a1`.
Its release fixes launcher CPU usage for newer clients; server and addon content match 0.1.36.
For this registered source installation, select **This PC (own server)**, address `127.0.0.1`, portal
`trinity.actual.battle.net`, region group 8, and game folder `F:\Games\World of Warcraft`. Press **Start server**,
wait for **Server ready**, then **PLAY NOW**. Keep build/update under these scripts rather than the repack updater.

The standalone launcher's **Start server**, **Stop server** and **Restart** actions are connected to this existing
source build by `Install-LauncherIntegration.ps1`, which `Play.ps1` runs before opening the launcher. Small marked
scripts under `tools\repack` call `launcher_control.py` and the maintained lifecycle code. Start waits for all game
listeners and a successful world-thread server-info response before printing **Server ready**. Stop saves the world
and waits for MySQL to finish flushing; Restart performs that stop before starting again.

The initial Stop-only fix supplied the missing `tools\repack` working directory. Start also needed the launcher's
installation check: the integration now registers the completed source installation using a **non-secret guidance
file** at `tools\secrets\first-login.txt`. It contains no password; the launcher only tests its existence. Supported
developer path files point server settings at the actual `server` directory and Restart at our adapter. Existing
unmanaged files are preserved with an error, rather than overwritten. `Install-LauncherStop.ps1` remains a compatibility
entry point for the full installer. No launcher binary, database, certificate or account is replaced by integration.

An offer to install the packaged repack is unnecessary for this workspace: choose **No**. The launcher may still show
an unknown *repack* version because this is a source build. That label is not a server-readiness check. For backup,
restore and updates, continue using the source commands below; other repack management buttons are not declared supported.

## Run and play

```powershell
.\source\local-server\Server.ps1 start
.\source\local-server\Server.ps1 status
.\source\local-server\Server.ps1 check
# Run once after clean world startup; uses native bnetaccount create, with credentials saved privately.
.\source\local-server\Server.ps1 create-account
.\source\local-server\Play.ps1
.\source\local-server\Server.ps1 stop
```

The created local login is `aleksander@forever.local`, with a random password in `local\secrets.json`. It is a server-local
account, not a Blizzard account. `create-account` preserves an existing account and needs a running world server.
`Show-Login.ps1` opens a local window containing only this playing account, with the password masked by default and
explicit reveal/copy controls. It never prints credentials, creates another credential file or copies automatically.
This revision allows all accounts to control their own companions. The game account stays normal; the separate `FFADMIN`
account is used only for local lifecycle commands. Do not use GM levelling, gear or teleport commands for progression checks.

In game `/fb` opens the panel. `.bot add warrior tank`, `.bot add priest healer`, `.bot add mage dps` and another damage
bot make a party with a damage-dealing player. Party words `follow`, `stay`, `attack`, `pull`, `flee`, `release` and `help`
give orders; `.bot call all` recalls saved bots. `.bot save all` saves the roster. See
[BOT_COMMANDS.md](../src/modules/PlayerbotV2/BOT_COMMANDS.md) for formations, dungeon finder, raid assignments and limits.
The addon is required for reliable whispers on this client.

If login reaches gameplay-ruleset selection but Normal says no realms are available, check `Realm.AlsoAcceptBuilds`
in **both** bnetserver.conf and worldserver.conf. The realm's native advertised build is 70707; this installation's
verified compatibility list includes 70938,70888,70862. An empty login-server list hides it from build 70938 even if
worldserver already accepts that build. `python source/local-server/configure.py` preserves other settings and migrates
this one key in existing configs. Restart the login server after changing it (its accepted list is cached).

## Local gameplay choices

Edit `server\worldserver.conf.d\zzzz-aleksanderG.conf` and restart. It loads after upstream templates.
The machine is a Ryzen 7 7800X3D with about 32 GB RAM. Initial roaming settings: reserve 200, active cap 60,
15–25 per occupied levelling zone and 30 in an occupied city. No local language-model service is enabled.

Companions, proximity-spawned roaming bots and the auction-house bot are **enabled**. On 16 November the user also
enabled automatic battleground queueing (`Playerbot.Bg.AutoJoin = 1`), one automatically seeded bot-only BG at a time
(`Playerbot.Bg.AutoSeed.Matches = 1`), and instant dungeon travel (`Playerbot.Lfg.Finder.Enable = 1`). Automatic arena
seeding remains off. Existing ambient BG defaults remain: 3% roll per eligible bot/minute, up to 24 queued, two additions
per tick, minimum level 10. BG match rosters are separate from the roaming cap and can add active bots.
LLM chat and cast-speed overrides remain disabled. `playerbot.conf` contains an earlier
`Playerbot.World.Enable = 0`, but the personal override below sets it to 1. Read effective settings, not one file alone:
the core loads worldserver.conf first, then .conf files under worldserver.conf.d in alphabetical order, with later values
winning. Put personal choices in `server/worldserver.conf.d/zzzz-aleksanderG.conf` so upstream presets do not override them.
Set `Playerbot.World.Enable = 0` there to disable roaming while retaining companions and the AH bot, or
`Playerbot.Enable = 0` to disable the playerbot module (the separate auction bot has its own seller/buyer switches).
The AH bot targets 400 white, 300 green and 100 blue items, zero epic items, with a level-60/item-level-65 ceiling.
Players still pay for purchases and earn their gear. Raid shortcuts, faster casting and auto raid gear/enchants are off.
Owned bots use only `match` gear mode. Upstream still generates level-appropriate companion gear; this is not a system
where every companion starts naked and earns every item. Player XP, gold and drop-rate multipliers retain core defaults.
Kill/quest/exploration XP and ordinary loot/gold rates are 1. **Rate.XP.DungeonKill is 1.8**, the upstream Forever default
for extra XP in five-player dungeons on top of the normal kill calculation; it does not apply to raids. Earlier blanket
statements that all XP rates were 1 were incomplete. Set this key to 1 if choosing the older vanilla dungeon XP behavior;
no such gameplay change has been made merely to document this distinction.
Extra bot groups in Group Finder are limited to two listings / ten bots. The user-enabled `.bot dungeon` finder can form
a party and transport it to a suitable dungeon: `.bot dungeon` lists choices, `.bot dungeon <word> [tank|healer|dps]`
queues, and `.bot dungeon leave` returns you. Normal eligibility and entry restrictions still apply; this does not grant
levels or bypass attunements. These newly enabled BG/dungeon features still need real gameplay validation.

`Classic.ForeverCreatureHealth = 0` and `Classic.ForeverKillXp = 0` are unchanged. The health option uses the fitted
`creature_classic_classlevelstats.health_forever` curve for mapped vanilla creatures, falling back to vanilla health if
no Forever value exists. It is not a uniform multiplier or an exact sniff for every individual creature. Installed base
health examples at level 60: class 1 is 3052 -> 4365 (+43%); class 8 is 2136 -> 4365 (+104%), before individual creature
multipliers. The XP option changes only below-player-level kills to use the mob's base XP rather than the player's:
player 10/mob 8 gives 61 rather than 68 base XP; equal/higher and gray-level behavior is unchanged. Upstream attributes
this formula to another project's sniff analysis and explicitly marks it as not independently verified. Both are
optional balance changes, not general compatibility fixes, and were not enabled by the BG/dungeon request.

`QuestDrops.GuaranteeOrdinaryCollection = 1` enables the small source customization; set 0 and restart to disable.
Its default in the public config template is **off**. It changes no SQL rows and survives normal DB updates.

Covered: direct, ungrouped, positive-chance quest-only **creature corpse** item rows; the item must be quest class,
common quality or lower, unequippable, not a quest starter, without ignore-quest-status or follow-loot-rules flags.
An eligible nearby player must have an incomplete, mandatory item objective that the core says is currently completable,
and still need the item including bank holdings. Existing conditions, loot modes, group access and min/max quantities remain.
References deliberately do not inherit the guarantee. Loot groups, gathering, containers, personal encounter loot,
equipment, higher-quality/optional collectibles, source-item chains and other special loot retain existing rolls.
This is a defined subset, not a promise of 100% drops for every quest item.

## Explicit updates and rollback

```powershell
.\source\local-server\Update.ps1 -PreviewOnly
.\source\local-server\Update.ps1 -Jobs 6
```

The updater requires a completely clean `aleksanderG` working tree, fetches **only upstream forever-bots**, and shows
the commits and diff summary. Preview stops there. An actual update stops the world cleanly and backs up all five
databases, configs, credentials, certificates, installed executables/DLLs and the running build manifest before merging.
Conflicts stop the operation with the old binaries preserved and the server stopped: resolve and commit, or use
`git -C source merge --abort`. Rebuild and test, refresh the client addons with backups, then start; core/auth/custom SQL and bot migrations run from the source
tree at startup. The script waits for server info and listener checks; inspect logs and do login/save/reconnect before
pushing the merge. Nothing runs in the background or at boot. No release updater overwrites custom binaries.

```powershell
.\source\local-server\Server.ps1 backup
python .\source\local-server\verify_backup.py '.\backups\<timestamp>'
# Deliberately replaces the five application databases; keeps a safety backup first.
.\source\local-server\Server.ps1 restore '.\backups\<timestamp>' -ConfirmReplace
.\source\local-server\Server.ps1 start
.\source\local-server\Server.ps1 check
```

Backups leave the world stopped and MySQL running (starting only MySQL if needed, so a broken game executable can still be recovered).
Verification restores into a new isolated MySQL on port 3318,
compares schema counts and checks the dump checksum; it does not write production databases. Test files are retained
privately for inspection. Keep regular backups on another physical disk too.

If an update migrates databases, reverting an executable alone can be unsafe. `restore` restores matching databases,
configs and binaries together and creates a detached worktree at the backup's running source commit so startup sees
the matching migration files. It does not reset `aleksanderG` or discard later commits. Restoring is for this installation;
it preserves the current MySQL root credential and restores the server user's password to match the backed-up configs.
After recovery, reconcile the customization branch deliberately before the next update.
Extracted assets are not duplicated in the database backup. `data-manifest.json` records their client version; restore
refuses a mismatched version, so retain/re-extract matching data from your own compatible client before such a rollback.

## Verification and discovered limitations

Do not mark these passed without evidence. Current results are in SESSION.md.

The 17 November upstream update passed 1,114 game test cases (321,175 assertions), 187 tooling test cases
(29,950 assertions), the 22 quest-policy assertions, migration execution checks, and native Windows TLS 1.3 validation.
Player progression, inventory, quest progress, configuration and TLS files matched their pre-update fingerprints.
The server is running; a real-client login and gameplay check after this update remains pending. See SESSION.md for recovery details.

Earlier verification on 15 November 2026: the source build, 22 quest-policy assertions, migrations, extraction, native server commands,
loopback listeners, TLS diagnostics, human/orc offline paths and an isolated backup restore passed. Normal game account
creation and graceful stop/restart also passed. The user is now playing a level-1 human warrior in Northshire Valley;
real login/world entry and native saving of the character and quests passed. Services remain running for play.
Reconnect, party, dungeon and collection-drop checks below remain pending; startup has the data warnings listed here.

- Build, quest regression tests, all five DB migrations and clean startup; verify listeners are loopback only.
- Real client: log in, create a character, enter the world, gain/loot something, log out and reconnect; confirm save state.
- Add tank/healer/DPS companions, check follow/attack/healing and persistence; do a suitable normal dungeon when level permits.
- Collection: quest 60 **Kobold Candles** from William Pestle needs 8 of item 772, or quest 83 **Red Linen Goods** from Sara
  Timberlain needs 6 of item 1019. Loot after each eligible kill. Confirm the requested number, then kill more and check
  there are no extra quest-only drops, while ordinary money/equipment still behave normally. Check a group member who
  needs the item while you do not; test the toggle off and verify grouped/reference loot remains unaffected.
- Create a backup and run the isolated restore verification. In-game dungeon and loot tests require an observable client.

Discovered in actual source/docs:

- **Manor Mistmantle (3109):** the client names this map, but no instance-template row, creature spawns or gameobject
  spawns were present after all migrations, and its navigation mesh could not be built. Treat this content as unverified
  and incomplete here. Test Dungeon (13) also has no mesh. The other 74 maps produced meshes; all six starter tiles passed.
- **Iron Kingsguard (274781):** repeated invalid display-model variants 147966/147968 occur during runtime initialization;
  affected guards can fail to load. These model records still need correction. DBErrors and Playerbot logs now retain
  at most three 16 MB rotated files plus the current file. Startup reaches ready state but is **not warning-free**.
- Border-tile MMAP warnings also occur in battleground preloading. Human/orc starting-area offline paths passed; this
  does not validate battleground gameplay. Bot generation also emits some unknown-spell diagnostics requiring live checks.
- City of Dalaran boss timers/damage and some access behavior are explicitly **INFERRED**. Grindle Firespark has no spawn
  in the cited source data, so the Prismatic Doors use an inferred three-boss condition.
- The Drowned City scripts explicitly use inferred timings/damage; no live fight capture is cited.
- Excavation Site: Wetlands says its bosses other than Relic Guardian have no custom scripts in that file; encounter
  tracking is shared, and the Guardian's activation behavior/timers are inferred.
- Bot docs list unimplemented ike3 `co`/`nc`/`ss` strategy toggles, a two-step `repair` from a distance, `loot all` resetting
  on relog, and unverified whisper-prefix/right-click behavior. The module install guide notes four legacy read paths still
  using character-DB copies despite shared copies being established. Do not run old partial source over this checkout.
- Supporting client build 70938 does not verify the whole official Forever world, every class, every quest or every raid.
  Full raid play has not been validated here. Keep normal attunements and other challenge rules until choosing otherwise.
