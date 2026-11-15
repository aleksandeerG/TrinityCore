# Adapt the verified standalone launcher's Stop button to this source-built installation.
# Its ServerOps.Run uses <launcher directory>\repack as both script location and working directory.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$launcher = Join-Path $root 'tools\WoWForeverLauncher.exe'
if (!(Test-Path -LiteralPath $launcher)) { throw 'The verified standalone launcher is missing.' }
$directory = Join-Path $root 'tools\repack'
if (!(Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory | Out-Null }
$target = Join-Path $directory 'Stop-WoWForever.ps1'
$marker = '# forever-source-build-stop-adapter-v1'
$adapter = @'
# forever-source-build-stop-adapter-v1
# Installed by source/local-server/Install-LauncherStop.ps1. No repack binaries or database scripts are used.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$serverScript = Join-Path $workspaceRoot 'source\local-server\Server.ps1'
if (!(Test-Path -LiteralPath $serverScript)) { throw 'The source-built server lifecycle script is missing.' }
& $serverScript stop
if ($LASTEXITCODE) { exit $LASTEXITCODE }
'@
if (Test-Path -LiteralPath $target) {
    $existing = Get-Content -LiteralPath $target -Raw
    if (!$existing.StartsWith($marker)) { throw 'An unmanaged shutdown script already exists; preserved it without replacement.' }
    if ($existing -eq $adapter) { Write-Output 'Launcher Stop adapter is current.'; return }
}
$parseErrors = $null
$tokens = $null
[Management.Automation.Language.Parser]::ParseInput($adapter, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors) { throw 'Generated launcher Stop adapter failed PowerShell parsing.' }
[IO.File]::WriteAllText($target, $adapter, (New-Object Text.UTF8Encoding($false)))
Write-Output 'Launcher Stop now delegates to Server.ps1 stop (save, world shutdown, login shutdown, database flush).'
