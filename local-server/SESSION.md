# Continuation state — 15 November 2026

Task: source-built local WoW Forever with companion/world/AH bots, normal progression, scoped collection-drop guarantee,
fork workflow and safe manual updates/backups. User's full original request was supplied as an attachment.

## Verified completed

- Empty target workspace inspected; no prior server or saves were present. Existing game installation preserved.
- GitHub authenticated account `aleksandeerG`; fork created/reused: https://github.com/aleksandeerG/TrinityCore.
- `source` cloned from upstream `forever-bots` at `51b5ae0971fadf2e96a16b4730e986cc33e29adb`.
  `origin` is the fork; `upstream` is Karrz1/TrinityCore. Clean `forever-bots` tracks upstream; custom `aleksanderG` tracks origin.
  Both initial branches pushed. Quest implementation committed as `027ce55378` (tests still pending at this point).
- No applicable AGENTS.md found in workspace ancestors or the cloned tree; README, contribution/setup docs, module docs,
  release v0.1.36.1 notes and actual relevant code/schema inspected.
- User confirmed client installation finished. `.build.info` and executable string version are `1.60.1.70938`, product `wowf`.
  Manifest and upstream auth migration accept it; current source uses 70790 packet mapping until newer differences are known.
- Source-matched ForeverBots and ForeverDots addons installed in `_forever_\Interface\AddOns`.
- Visual Studio 2022/MSVC 19.43, CMake 3.30.5, Ninja available. Ryzen 7 7800X3D, ~32 GB RAM, ~4 TB free on F:.
- Portable MySQL 8.4.7 installed under dependencies. Isolated instance on 127.0.0.1:3317, X protocol off; random root/server
  passwords in `local\secrets.json`, never print or commit them. No Windows service or boot autostart.
- All initial DB imports succeeded: ff_auth 39 tables, ff_characters 132, ff_world 265, ff_hotfixes 483, playerbot 56
  (counts include views). Auth startup migrations subsequently passed in a diagnostic login-server run; world/hotfix/character
  and bot startup migrations have **not** been verified yet.
- World/hotfix release is `forever-tdb-2026-10-14`. Initial world/auth schemas still require normal startup migrations.
- Source customization guarantees eligible ordinary direct ungrouped quest-only creature rows; default off, local profile on.
  Tests added. Uses core pending-objective/condition checks, normal group access/counts. Read README for exact exclusions.
- Scripts/templates added under local-server; PowerShell parse and Python syntax checks passed at time of writing.
  Update.ps1 correctly refused a dirty tree before fetching. Config renderer replacement/preservation checks passed.
- QuestCollectionLoot tests passed: **22 assertions, 2 test cases**. Both modified loot .cpp files compiled successfully.
- Diagnostic source-built bnetserver startup passed with numeric advertised REST addresses in a separate private test config.
  TLS **1.3** chain and hostname verification passed using a per-test CA file; Windows trust and hosts were unchanged.
  Auth now has 585 migration ledger rows, latest 2026_11_13_70_auth_classic_70938.sql. Realm 70/region 70/battlegroup 1,
  gamebuild 70707; build_info contains 70938, 70888 and 70707 as 1.60.1. This is not a real-client login test.
- Current launcher downloaded from v0.1.36.1, SHA256 verified against its release checksum manifest.
- Generated private scoped certificates in local/certs. Both trust import and hosts UAC prompt were canceled; neither change
  has been confirmed. `local`, `server`, `backups` ACLs restrict access to danal, SYSTEM, Administrators.

## User steering — do not lose this

The user asked what the certificate/hosts change was needed for, then asked whether it could be done another way.
Explained exact loopback mapping, restricted CurrentUser trust, manual setup/VM alternatives. **No approval to retry
the prompts has been given.** Continue independent server work. Do not keep asking or silently retry trust/elevation.
Never bypass TLS validation or open network services to solve this. In-game connection tests remain pending.

## Active work / next steps

- Full source build **passed** and was installed via `Build.ps1`; inspect `inspection/source-build.log`.
  Installed manifest: 027ce55378cf0ecf88e610989b460eefcf240200, RelWithDebInfo, botModule true, built 2026-11-15 16:29 UTC.
  Quest tests passed again against the final shared-OpenSSL build (22 assertions / 2 cases).
  Initial builds uncovered missing Boost headers; all direct modules and Boost.Process were subsequently installed.
  vcpkg baseline 8f363bdc11359ede4bc51e5eb32a2617538049c8, Boost 1.92.0 static-md / OpenSSL 3.6.5 shared x64-windows.
  A fresh CMake configuration fixed empty compiler flags left by an early compiler-discovery failure.
- Windows command-line length required a reversible W: SUBST alias to the workspace. Runtime SourceDirectory and
  MySQLExecutable configs use full F: paths. Static OpenSSL caused duplicate AES symbols with CascLib in map/vmap extractor
  links; shared OpenSSL was built and the unused static package removed. Full incremental rebuild against shared headers/libs
  passed. Final source-built shared-OpenSSL bnetserver passed the TLS diagnostic too. No packaged server binaries were used.
- Extract.ps1 is running against the completed real client, tool session 38743; inspect `inspection/extraction.log`.
  Do not mark extraction complete until all stages and markers pass. Do not replace binaries/DLLs while extractors use them.
- Verify world startup/migrations independently; hostname/trust can block bnet/client until user chooses how to connect.
- Create game account through native server command once world is ready. Planned email `aleksander@forever.local`; random
  password already reserved in private secrets. No game account created yet. Latest own-bot commands need no GM.
- Verify server listeners, persistence where possible, backup and isolated restoration. Never claim unobserved in-game tests passed.
- Finish reviewing/testing lifecycle scripts (especially restore/update), commit them and these docs in small commits, push origin.
- Update this file with exact installed commit and evidence. Save a short root START-HERE.md for the user.

## Useful operational notes

Default sandbox runs as CodexSandboxOffline; network/elevated-tool calls run as danal. Git may reject ownership under
the sandbox: use `git -c "safe.directory=F:/Games/World of Warcraft Forever Trinity Core/source"` for a read-only check
or run as the owner. Do not add a global wildcard safe.directory. Private folders require owner-context execution.
PowerShell 5.1 native stderr plus ErrorActionPreference Stop can abort successful tools; Build.ps1 handles this explicitly.
Use Windows executable version **string**, not FileBuildPart (which truncates this five-digit WoW build).
The repack was downloaded only for checksum-verified documentation/launcher-script inspection; its server was not installed.

Follow README for commands and exact known content limitations. No client login, character, party, dungeon or quest-drop
gameplay test has passed yet. Backup/restore and full startup are pending, not completed merely because scripts exist.
