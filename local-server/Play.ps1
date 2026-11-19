[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$launcher = Join-Path $root 'tools\WoWForeverLocal.exe'
if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw 'Build the local launcher with Build-Launcher.ps1 first.'
}

$python = (Get-Command python.exe -CommandType Application -ErrorAction Stop).Source
Start-Process -FilePath $launcher -ArgumentList ('"' + $python + '"') -WorkingDirectory $root
