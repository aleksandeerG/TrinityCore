[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$launcher = Join-Path $root 'tools\WoWForeverLauncher.exe'
if (!(Test-Path -LiteralPath $launcher)) { throw 'Download the checksum-verified v0.1.36.1 launcher described in README.md.' }
$resolved = @()
try { $resolved = @([Net.Dns]::GetHostAddresses('trinity.actual.battle.net') | ForEach-Object { $_.ToString() }) } catch { }
if ($resolved -notcontains '127.0.0.1') { throw 'The local portal mapping is still pending. See Certificates.ps1 -HostsOnly.' }
$certFile = Join-Path $root 'local\ca-thumbprint.txt'
if (!(Test-Path -LiteralPath $certFile)) { throw 'The local certificate trust step is still pending.' }
$thumb = (Get-Content -LiteralPath $certFile -Raw).Trim()
if (!(Test-Path -LiteralPath "Cert:\CurrentUser\Root\$thumb")) { throw 'This Windows account does not trust the local login CA.' }
Write-Output 'In the launcher choose Join / a server you built yourself, address 127.0.0.1; select F:\Games\World of Warcraft.'
Write-Output 'Use the credentials in local\secrets.json. Start the client with the launcher each time.'
Start-Process -FilePath $launcher -WorkingDirectory $root
