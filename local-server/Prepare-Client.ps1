[CmdletBinding()]
param([string]$Client = 'F:\Games\World of Warcraft')
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$root = Split-Path $source -Parent
$game = Join-Path $Client '_forever_'
$exe = Join-Path $game 'Wow.exe'
if (!(Test-Path -LiteralPath $exe)) { throw "Forever client not found: $exe" }
$version = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
if ($version -notmatch '\.(\d+)\s*$') { throw "Cannot read the full client build from version: $version" }
$build = [int]$matches[1]
if ($build -notin @(70938,70888,70862)) { throw "Client build $build needs upstream compatibility review before setup." }
$addons = Join-Path $game 'Interface\AddOns'
New-Item -ItemType Directory -Path $addons -Force | Out-Null
foreach ($name in @('ForeverBots','ForeverDots','ForeverCombatNameplates')) {
    $from = Join-Path $source "src\modules\PlayerbotV2\Addon\$name"
    $to = Join-Path $addons $name
    if (Test-Path -LiteralPath $to) {
        $backup = Join-Path $root ('local\client-addon-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "\$name")
        New-Item -ItemType Directory -Path (Split-Path $backup -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $to -Destination $backup -Recurse
    }
    # Validate explicit resolved client and workspace paths before copying this addon directory.
    if (![IO.Path]::GetFullPath($to).StartsWith([IO.Path]::GetFullPath($addons) + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Addon destination escaped AddOns.'
    }
    Copy-Item -LiteralPath $from -Destination $addons -Recurse -Force
}
Write-Output "Installed the source-matched ForeverBots, ForeverDots and ForeverCombatNameplates addons for client build $build. In game: /fb"
