# Continuation state - 15 November 2026

The server setup, authorized one-leaf TLS/hosts connection setup, real-client login, character creation/world entry and native saving are verified. Save/reconnect, companion-party, dungeon and collection-loot gameplay checks remain pending. Do not declare the entire original request complete.

## User intent and latest steering

User requested a locally hosted real WoW Forever server with optional companion, roaming and auction bots, normal progression, a narrowly scoped collection-drop guarantee, a maintained GitHub fork, and safe manual update/backup/rollback commands. No official-server automation, global loot/XP boosts, automatic BiS gear, router exposure or boot startup.

After discussing alternatives, the user explicitly authorized a new hostname-restricted CA, one longer-lived server certificate, destruction of the signing key, per-user trust and the hosts entry ("let's do this"). Applied the agreed five-year design: the NEW CA signing key was generated only in memory and never serialized; exactly one leaf was issued. No VM/sandbox or separate gaming account was created. Do not bypass TLS verification.

## Authorized connection setup - 15 November 2026

- `local/certs/profile.json`: profile forever-single-leaf-v1, CA thumbprint A89AECD5DAC82543DAB4911F1D9CA5F038D112FB. CA RSA-4096, leaf RSA-3072, SHA-256 signatures. Leaf expires 2031-11-15T21:30:04Z; CA expires 2031-12-15T21:30:04Z.
- CA critical DNS constraints permit trinity.actual.battle.net and exclude its descendants (.trinity.actual.battle.net), path length zero, server-authentication EKU only. Leaf SAN contains only the exact hostname, CA=false, server-authentication only. Root constraint enforcement varies by verifier; do not promise universal hostname scoping across applications.
- The new signing key was never written/exported, and its generation process exited. Only the server private key remains on disk. This does not guarantee absence from OS memory/pagefile/crash-dump traces. Removed the old, untrusted live certificate files including ca.key. Older private backups still contain that OLD, untrusted CA/key; do not claim those copies were securely erased.
- New CA trusted only under danal CurrentUser Root, not LocalMachine Root. Exactly one tagged 127.0.0.1 trinity.actual.battle.net hosts line added with UAC; previous bytes are in local/hosts-before-forever.bin.
- OpenSSL security tests passed: exact DNS accepted; subdomain and unrelated-domain leaves rejected by constraints; wrong hostname and wrong TLS purpose rejected; no CA key output; profile tampering rejected.
- Compiled bnetserver passed explicit-CA TLS 1.3 diagnostic. Normal configuration then passed native Windows SslStream TLS 1.3 with no validation callback; unrelated hostname rejected. Report: local/windows-tls-verification.json. Login listeners stayed on loopback.
- Normal start exposed/fixed a missing socket import in manage.py (the earlier world-only path did not exercise it). Server start now validates the hardened TLS profile. Play also validates it. Backup excludes ca.key, and restore preserves the current one-leaf identity when restoring older database snapshots.
- Full normal start and SOAP server-info checks passed after installing the connection setup. MySQL 3317, login 1119/8081, world 8085 and SOAP 7878 listeners were all verified as 127.0.0.1 only. New hosts bytes were verified to equal the saved original plus only the exact tagged append. The saved server key ACL grants only danal, SYSTEM and Administrators.
- Trust undo remains Certificates.ps1 -Undo as danal; hosts undo is Certificates.ps1 -HostsOnly -Undo as Administrator. They are two separate commands. Host undo preserves unrelated bytes/edits.
- The user requested help with the launcher/password. Launcher accessibility labels confirmed the selected server is "This PC (own server)", address 127.0.0.1, portal trinity.actual.battle.net, region group 8. Wow.exe is running. Show-Login.ps1 displays only the game account locally, masked by default, with explicit reveal/copy controls and no credential stdout/file copy. Hidden PowerShell startup also hid the initial dialog; it was brought into view, the duplicate helper was closed, and the helper now explicitly shows its form on Shown.
- User then reached gameplay-ruleset selection, but Normal reported no realms. Found effective bnetserver.conf still had Realm.AlsoAcceptBuilds="" while worldserver.conf accepted 70938/70888/70862; configure.py had preserved the earlier default-empty file. Backed up bnet config privately, migrated only the accepted-build key, and restarted only login (world process preserved). Both now have the same accepted list. configure.py migrates that key in earlier preserved configs, and restore reapplies it. The user subsequently confirmed successful world entry. The latest full backup predates this compatibility-key correction, but the current restore helper reapplies it.

## Real-client world entry and saving - confirmed 15 November 2026

- User reported: "i am in game in northshire valley and got my first quest" after retrying Normal with the corrected login build list. This confirms real client login and world entry, not merely a diagnostic handshake.
- Read-only DB checks confirmed playing account 2 (1#1) online, security level 0; new character GUID 316, level 1, human warrior, map 0/zone 12. No levels, gear, quests or teleport shortcuts were granted.
- Ran native `saveall` without disconnecting the player; server replied "All players saved." Confirmed the character and quest rows 7/status 3 and 5261/status 1 in the character DB. Report: local/client-world-entry-verification.json (2026-11-15T21:55:48Z).
- Native saving is verified; logout/reconnect persistence has not yet been confirmed. Party controls, dungeon gameplay and ordinary quest-item drops remain unverified. First Northshire kill quests do not constitute a collection-drop test.
- Keep the game/server running while the user plays. Do not restart or back up in a way that disconnects them without coordinating a stopping point. The latest full backup predates this new real-player character; make a fresh backup at a coordinated stopping point.

## Repository and installed build

- Workspace: F:\Games\World of Warcraft Forever Trinity Core. Git checkout: source.
- Fork: https://github.com/aleksandeerG/TrinityCore. GitHub account spelling is aleksandeerG; custom branch spelling is aleksanderG.
- origin is the fork; upstream is https://github.com/Karrz1/TrinityCore.git.
- Clean forever-bots tracks upstream/forever-bots at 51b5ae0971fadf2e96a16b4730e986cc33e29adb. Custom branch tracks origin/aleksanderG.
- Installed C++ source: **027ce55378cf0ecf88e610989b460eefcf240200**, RelWithDebInfo, BUILD_PLAYERBOT_V2=1. server/build-manifest.json is authoritative.
- Later commits contain scripts/docs/extraction fixes, not additional runtime C++ changes. Read git log for the latest operations commit. All custom work is pushed to the fork at handoff; no upstream PR was submitted.
- The separate Karrz-playerbots-wow-forever main repository still describes its source as an older partial copy. It was used for current release documentation/launcher only, never copied over this source tree. Packaged server binaries were not used.
- No applicable AGENTS.md found in workspace ancestors or the clone. README, contribution/setup/module/bot docs, current release notes, source loot code and actual DB schemas were inspected.

## Paths, dependencies and final service state

- Installed executables, private configs, extracted data and logs: server.
- Private credentials, CA/keys, MySQL data: local. Backups: backups. These are outside Git and have owner/SYSTEM/Administrators ACLs.
- Game: F:\Games\World of Warcraft, product wowf, _forever_\Wow.exe, **1.60.1.70938**. The user confirmed installation complete. Current release manifest and auth migration accept this build; source uses the 70790 packet mapping until newer differences are found.
- Ryzen 7 7800X3D, ~32 GB RAM, ample F: disk space.
- VS 2022/MSVC 19.43, CMake 3.30.5, Ninja; MySQL 8.4.7 portable; Boost 1.92.0 static-md; OpenSSL 3.6.5 shared x64-windows; vcpkg baseline 8f363bdc11359ede4bc51e5eb32a2617538049c8.
- Shared OpenSSL is essential: static libcrypto collided with bundled CascLib AES symbols in extractor linking. All targets and quest tests subsequently passed.
- Build.ps1 uses a reversible short drive alias to avoid Windows command-line length limits. W: was removed and runtime restart was verified without it. SourceDirectory, MySQLExecutable and BuildDirectory use full F: paths in configs.
- **The local server is running for client connection testing; the Forever launcher and game are open.** No Windows services, boot startup, firewall exceptions or router forwarding were installed. Runtime listeners were verified as only 127.0.0.1:3317 (MySQL), 7878 (SOAP), 8085 (world), 1119 and 8081 (login). MySQL X protocol is disabled. RA is off.

## Verified results

- Source build installed successfully, including bot module and all tools. QuestCollectionLoot tests passed: **22 assertions / 2 cases**. PowerShell parsing and Python compilation checks passed.
- All core/custom and bot migrations applied. Schema/view counts: ff_auth 53, ff_characters 161, ff_hotfixes 484, ff_world 278, playerbot 61. Base release forever-tdb-2026-10-14; current source also replays changed historical custom SQL, so expect migrations beyond newly dated files.
- Realm 70, region 70, battlegroup 1, database gamebuild 70707; accepted build_info includes 70938/70888 as 1.60.1. Both bnet and world configs accept those builds.
- Full extraction passed in about 23 minutes: 1133 dbc files, 6868 maps files, 13096 vmap files, 3234 mmap files; 74 maps have navmeshes. Total generated final data ~2.63 GB. All six starter navigation tiles exist. server/data-manifest.json records client version and tools source commit.
- Windows PowerShell 5.1 incorrectly treated benign native stderr warnings as fatal. The maintained extraction script now logs stderr, checks real exit codes, quotes spaced paths for mmap generation, and validates intermediate cleanup targets. Completed maps/vmaps were resumed successfully.
- Offline Detour path probes at actual human and orc starting positions both returned complete paths, exit 0. Logs: inspection/navigation-probe-human.log and navigation-probe-orc.log. This is not an in-game bot-control test.
- Final source-built login server started and passed TLS 1.3 chain/hostname validation with an explicit per-test CA file, without changing Windows trust/hosts. Actual listeners were loopback-only. Diagnostic config advertises numeric REST addresses only for the test; normal config remains unchanged.
- World/module initialization reached ready state. Native server info, bot world, and auction status commands worked. Roaming mode was enabled with cap 60; roster generation produced level 1-60 bots. Actual offline roster can exceed the configured reserve because of upstream pool balancing; it is not a strict 200-character ceiling.
- Auction bot was listing stock; status showed zero purple/orange/yellow targets. Effective player XP and ordinary loot rates were verified as 1, Expansion 0, MaxPlayerLevel 60, RaidGear 0, RaidEnchants 0, owned gear mode match.
- Normal local login created through native bnetaccount create: **aleksander@forever.local**, game account **1#1**, GM/security level **0**. Password is local/secrets.json field game_password. Never print or commit any credentials. FFADMIN is a separate private console account, not the playing account.
- Source-matched ForeverBots and ForeverDots addons installed under _forever_\Interface\AddOns. /fb opens controls. Own-bot commands use normal-player permissions in this revision (confirmed in Commands/cs_playerbot_v2.cpp).
- Graceful stop/start and immediate restart passed with no W: alias. Lifecycle tests found/fixed a process-exit image-query race and mysqladmin returning before InnoDB released ibdata1. Stop now waits for the actual MySQL process to exit. Backup/restore can start only MySQL from a stopped state, without booting a broken game executable.
- Update preview passed on a clean tree and correctly rejected a dirty tree. It fetched only upstream forever-bots, found no changes, and did not merge or migrate anything.

## Backups and recovery evidence

- **Latest backup:** backups/20261115T213559949958Z, created after installing the one-leaf TLS identity. SQL dump 990849043 bytes. Includes the new public CA/server certificates, server key and profile, with no CA signing key. Previous setup backup: backups/20261115T172439867172Z.
- The latest backup passed an actual isolated restore on 127.0.0.1:3318: SHA-256 21a9f3bf36d6ca7cefe6aab1f70c1dee974f3e5d84dfb3ec4cd98fa21a268ded; all five schema counts matched (53/161/484/278/61 for auth/characters/hotfixes/world/playerbot). Critical counts matched: 34 game accounts, 33 BNet accounts, 1 realm, 315 characters including generated bots, 107335 bot names. Test MySQL stopped cleanly; production was not replaced. Report: backups/20261115T213559949958Z/restore-check.json.
- **Isolated restore actually tested:** backups/20261115T165445573260Z. SQL dump 986825689 bytes, SHA256 fd3c9f455792a67c348e453e4f83539000a43dea1b4eb67c5b86e8165b29606b.
- Restored into a new temporary MySQL on 127.0.0.1:3318, compared all five schema counts and critical row counts, then shut it down. Production data was not replaced. Report: that backup's restore-check.json and inspection/backup-restore-check.log.
- Verified snapshot critical rows: 2 auth accounts, 1 BNet account, 1 realm, 3 characters (AH sellers, not real-player characters), 107335 shared bot names.
- The older 172439 backup was not separately imported. The newest 213559 backup and earlier 165445 backup both passed isolated SQL restoration. The production-replacement restore path has not been exercised.
- Recovery commands and matching-source worktree behavior are in README.md. Roll back matching DBs/configs/binaries together, not an executable alone after migrations. Extracted assets are not duplicated in DB backups; data-manifest compatibility is checked.

## Gameplay choices and known limitations

- Configuration clarification after user asked about seeing bots: companions, roaming and AH bots are enabled as originally requested. LLM chat, automatic BG participation, cast-speed overrides and instant dungeon travel are off. Main config is followed by alphabetically sorted extra .conf files; zzzz-aleksanderG.conf wins over the earlier Playerbot.World.Enable=0 in playerbot.conf. No gameplay settings were changed in response to that question.
- XP correction: kill/quest/exploration multipliers are 1, but Rate.XP.DungeonKill is 1.8 (upstream Forever default, five-player dungeons only, on top of the normal kill calculation). Earlier blanket statements that all player XP multipliers were 1 were incomplete. Retained this setting pending the user's preference; the docs/template comment now state it explicitly.

- Local override: server/worldserver.conf.d/zzzz-aleksanderG.conf. Roaming cap 60, reserve configuration 200, 15-25 per occupied zone, 30 per city. Listed LFG groups capped at two / ten bots. No language-model service enabled.
- Raid shortcuts and free raid gear/enchants are off. Player XP/drop multipliers are 1. AH targets 400 white / 300 green / 100 blue / 0 epic. Owned companion gear is generated level-appropriate gear, not a system where bots earn every piece from scratch.
- Instant .bot dungeon teleporter is off to preserve travel/exploration; use the addon or .bot lfg <your role>, then travel to the dungeon entrance normally.
- QuestDrops.GuaranteeOrdinaryCollection=1 locally, default off in public core template. Direct, ungrouped positive-chance quest-only creature corpse rows, ordinary common-or-lower quest-class items, incomplete mandatory item objective and normal condition/group eligibility. No references/groups/gathering/containers/equipment/starters/optional higher-quality collectibles. No SQL loot rewrite. Set 0 and restart to disable.
- **Manor Mistmantle (3109):** client map name confirmed with lookup map id. No instance template, creature spawns or gameobject spawns in the migrated world DB, and no navmesh generated. Treat content here as incomplete/unverified. Test Dungeon (13) also has no navmesh.
- **Iron Kingsguard (274781):** eight world spawns; invalid display variants 147966/147968 repeatedly fail model validation. These records still need correction; affected guards can fail to load. DBErrors previously grew to ~151 MB, so DBErrors/Playerbot logs are now bounded to current + three 16 MB files. The server reaches ready state but startup is **not warning-free**.
- Battleground border-tile preload warnings and some unknown spell diagnostics (e.g. 73523/91404 during bot preparation) remain for live validation. Do not infer that every class/raid/BG works from a supported client build.
- Source scripts explicitly mark inferred Dalaran/Drowned City mechanics; Excavation Site has only partial custom boss scripting. Other documented bot gaps are in README/BOT_COMMANDS.md.

## Remaining work - requires observable real client

1. Hostname/per-user trust setup is complete and authorized; no further approval is needed for that scope. Consult the section above before rotating certificates or restoring legacy backups.
2. Start/check the full server and current checksum-verified WoWForeverLauncher.exe. See README/Play.ps1. Do not start Wow.exe directly or use Blizzard account credentials for the local realm.
3. Real-client login, character creation, world entry and native saving are confirmed. At a convenient stopping point, have the user log out and reconnect to confirm position/quests/inventory persist. Then coordinate a fresh backup including the new player character; the current backup command stops the world.
4. Verify a tank/healer/DPS party, commands and an appropriate dungeon at a normal level. No player XP/gear boosts were used for setup.
5. Verify collection quest 60 (Kobold Candles: 8 x item 772, William Pestle) or 83 (Red Linen Goods: 6 x item 1019, Sara Timberlain), no extra quest-only loot after need ends, unchanged unrelated loot, and group eligibility. These gameplay checks are **pending**, not passed.

Default sandbox user is CodexSandboxOffline; owner-context tool calls run as danal. Private folders require owner context. For sandbox Git reads use the exact per-call safe.directory, never a global wildcard. No skill/plugin delegated the work, and no sub-agents were used.
