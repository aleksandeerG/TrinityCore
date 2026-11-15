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
if (Test-Path -LiteralPath $certFile) { $thumb = (Get-Content -LiteralPath $certFile -Raw).Trim() }
else {
    # A manual certificate installation need not create the setup script's marker file.
    $caFile = Join-Path $root 'local\certs\ca.pem'
    if (!(Test-Path -LiteralPath $caFile)) { throw 'The local login CA has not been generated yet.' }
    $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $caFile
    $thumb = $certificate.Thumbprint
}
if (!(Test-Path -LiteralPath "Cert:\CurrentUser\Root\$thumb")) { throw 'This Windows account does not trust the local login CA.' }
& python "$PSScriptRoot\certificates.py" --check
if ($LASTEXITCODE) { throw 'The one-leaf TLS profile did not validate; client was not started.' }
Write-Output 'In the launcher choose Join / a server you built yourself, address 127.0.0.1; select F:\Games\World of Warcraft.'
Write-Output 'Use the credentials in local\secrets.json. Start the client with the launcher each time.'
Start-Process -FilePath $launcher -WorkingDirectory $root
