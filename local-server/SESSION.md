# Continuation state - 15 November 2026

The independent server setup and verification are finished. Real-client connection is pending the user's choice about hostname/certificate setup. Do not declare the entire original request complete.

## User intent and latest steering

User requested a locally hosted real WoW Forever server with optional companion, roaming and auction bots, normal progression, a narrowly scoped collection-drop guarantee, a maintained GitHub fork, and safe manual update/backup/rollback commands. No official-server automation, global loot/XP boosts, automatic BiS gear, router exposure or boot startup.

The user confirmed the client installation finished, then asked why the hosts/certificate changes were needed and whether another way exists. Both Windows prompts were canceled. **No approval to retry the prompts has been given.** Explained manual setup and an isolated Windows client VM as alternatives; a server-only VM does not remove client-side requirements. No documented method avoiding both requirements with the real unmodified client was found. Keep hosts/trust changes pending until their preference is resolved. Do not bypass TLS verification.

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
- **Everything is stopped cleanly at handoff.** No Windows services, boot startup, firewall exceptions or router forwarding were installed. Runtime listeners, when tested, were only 127.0.0.1:3317 (MySQL), 7878 (SOAP), 8085 (world), 1119 and 8081 (login). MySQL X protocol is disabled. RA is off.

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

- **Latest final backup:** backups/20261115T172439867172Z. It includes final configs/log caps, generated bot state, account data, binaries/DLLs, source and client-data manifests. Backup from a fully stopped state passed; all services were stopped again afterward.
- **Isolated restore actually tested:** backups/20261115T165445573260Z. SQL dump 986825689 bytes, SHA256 fd3c9f455792a67c348e453e4f83539000a43dea1b4eb67c5b86e8165b29606b.
- Restored into a new temporary MySQL on 127.0.0.1:3318, compared all five schema counts and critical row counts, then shut it down. Production data was not replaced. Report: that backup's restore-check.json and inspection/backup-restore-check.log.
- Verified snapshot critical rows: 2 auth accounts, 1 BNet account, 1 realm, 3 characters (AH sellers, not real-player characters), 107335 shared bot names.
- The later final backup was created/checksummed by the same tested mechanism, but was not separately imported again. The production-replacement restore path has not been exercised; the isolated SQL restoration has.
- Recovery commands and matching-source worktree behavior are in README.md. Roll back matching DBs/configs/binaries together, not an executable alone after migrations. Extracted assets are not duplicated in DB backups; data-manifest compatibility is checked.

## Gameplay choices and known limitations

- Local override: server/worldserver.conf.d/zzzz-aleksanderG.conf. Roaming cap 60, reserve configuration 200, 15-25 per occupied zone, 30 per city. Listed LFG groups capped at two / ten bots. No language-model service enabled.
- Raid shortcuts and free raid gear/enchants are off. Player XP/drop multipliers are 1. AH targets 400 white / 300 green / 100 blue / 0 epic. Owned companion gear is generated level-appropriate gear, not a system where bots earn every piece from scratch.
- Instant .bot dungeon teleporter is off to preserve travel/exploration; use the addon or .bot lfg <your role>, then travel to the dungeon entrance normally.
- QuestDrops.GuaranteeOrdinaryCollection=1 locally, default off in public core template. Direct, ungrouped positive-chance quest-only creature corpse rows, ordinary common-or-lower quest-class items, incomplete mandatory item objective and normal condition/group eligibility. No references/groups/gathering/containers/equipment/starters/optional higher-quality collectibles. No SQL loot rewrite. Set 0 and restart to disable.
- **Manor Mistmantle (3109):** client map name confirmed with lookup map id. No instance template, creature spawns or gameobject spawns in the migrated world DB, and no navmesh generated. Treat content here as incomplete/unverified. Test Dungeon (13) also has no navmesh.
- **Iron Kingsguard (274781):** eight world spawns; invalid display variants 147966/147968 repeatedly fail model validation. These records still need correction; affected guards can fail to load. DBErrors previously grew to ~151 MB, so DBErrors/Playerbot logs are now bounded to current + three 16 MB files. The server reaches ready state but startup is **not warning-free**.
- Battleground border-tile preload warnings and some unknown spell diagnostics (e.g. 73523/91404 during bot preparation) remain for live validation. Do not infer that every class/raid/BG works from a supported client build.
- Source scripts explicitly mark inferred Dalaran/Drowned City mechanics; Excavation Site has only partial custom boss scripting. Other documented bot gaps are in README/BOT_COMMANDS.md.

## Remaining work - requires user decision and observable real client

1. Resolve preferred connection setup. Certificate and key exist in local/certs, but trust import and hosts entry are NOT applied. Certificates.ps1 supports narrow CurrentUser trust and exactly one backed-up localhost hosts line, with separate undo commands. No permission to retry prompts has been given.
2. After authorization, establish the selected scoped setup; start the full server and current checksum-verified WoWForeverLauncher.exe. See README/Play.ps1. Do not start Wow.exe directly or use Blizzard account credentials for the local realm.
3. Verify actual login, character creation, entering the world, saving and reconnecting.
4. Verify a tank/healer/DPS party, commands and an appropriate dungeon at a normal level. No player XP/gear boosts were used for setup.
5. Verify collection quest 60 (Kobold Candles: 8 x item 772, William Pestle) or 83 (Red Linen Goods: 6 x item 1019, Sara Timberlain), no extra quest-only loot after need ends, unchanged unrelated loot, and group eligibility. These gameplay checks are **pending**, not passed.

Default sandbox user is CodexSandboxOffline; owner-context tool calls run as danal. Private folders require owner context. For sandbox Git reads use the exact per-call safe.directory, never a global wildcard. No skill/plugin delegated the work, and no sub-agents were used.
