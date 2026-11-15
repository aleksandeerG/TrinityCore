# Run as the playing Windows user while the local login server is running.
# SslStream uses normal Windows trust/hostname validation; no validation callback is installed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$profile = Get-Content -LiteralPath (Join-Path $root 'local\certs\profile.json') -Raw | ConvertFrom-Json
if (!(Test-Path -LiteralPath "Cert:\CurrentUser\Root\$($profile.caThumbprint)")) { throw 'Local CA is not trusted by this user.' }
if (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$($profile.caThumbprint)") { throw 'Unexpected machine-wide CA trust.' }
if (Test-Path -LiteralPath (Join-Path $root 'local\certs\ca.key')) { throw 'A CA signing key is unexpectedly retained.' }
$addresses = @([Net.Dns]::GetHostAddresses('trinity.actual.battle.net') | ForEach-Object { $_.ToString() })
if ($addresses.Count -ne 1 -or $addresses[0] -ne '127.0.0.1') { throw 'Portal does not resolve exclusively to localhost.' }
function Test-LocalTls([string]$ServerName) {
    $tcp = New-Object Net.Sockets.TcpClient
    $tls = $null
    try {
        $pending = $tcp.BeginConnect('127.0.0.1', 8081, $null, $null)
        if (!$pending.AsyncWaitHandle.WaitOne(15000)) { throw 'Local TLS TCP connection timed out.' }
        $tcp.EndConnect($pending)
        $tls = New-Object Net.Security.SslStream -ArgumentList $tcp.GetStream(),$false
        $tls.ReadTimeout = 15000
        $tls.WriteTimeout = 15000
        $tls.AuthenticateAsClient($ServerName, $null, [Security.Authentication.SslProtocols]::None, $false)
        return $tls.SslProtocol.ToString()
    } finally {
        if ($tls) { $tls.Dispose() }
        $tcp.Dispose()
    }
}
$protocol = Test-LocalTls 'trinity.actual.battle.net'
$wrongNameRejected = $false
try { $null = Test-LocalTls 'account.battle.net' } catch {
    $errorException = $_.Exception
    while ($errorException.InnerException) { $errorException = $errorException.InnerException }
    if ($errorException -isnot [Security.Authentication.AuthenticationException]) { throw }
    $wrongNameRejected = $true
}
if (!$wrongNameRejected) { throw 'Wrong TLS hostname was unexpectedly accepted.' }
$result = [ordered]@{ WindowsTrustVerified=$true; Protocol=$protocol; Hostname='trinity.actual.battle.net';
    ResolvedAddresses=$addresses; WrongHostnameRejected=$wrongNameRejected; TrustScope='CurrentUser';
    CAKeyOnDisk=$false; ServerExpiresUtc=$profile.serverExpiresUtc; RealClientLoginTested=$false }
$json = $result | ConvertTo-Json -Depth 4
$json | Set-Content -LiteralPath (Join-Path $root 'local\windows-tls-verification.json') -Encoding UTF8
Write-Output $json
