[CmdletBinding()]
param([switch]$HostsOnly, [switch]$Undo)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$private = Join-Path $root 'local'
$certs = Join-Path $private 'certs'
$hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$marker = '127.0.0.1 trinity.actual.battle.net # forever-aleksanderG-local'
if ($HostsOnly) {
    $original = if (Test-Path -LiteralPath $hostsFile) { [IO.File]::ReadAllBytes($hostsFile) } else { [byte[]]@() }
    $content = [Text.Encoding]::UTF8.GetString($original)
    if ($Undo) {
        # Remove only our exact line; preserve changes made by other software after setup.
        $lines = @($content -split "`r?`n" | Where-Object { $_ -ne $marker })
        [IO.File]::WriteAllText($hostsFile, ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
        Write-Output 'Removed this installation hosts entry only.'
        return
    }
    $active = @($content -split "`r?`n" | Where-Object {
        $words = ($_ -replace '#.*$', '').Trim() -split '\s+'
        $words.Count -ge 2 -and $words[1..($words.Count-1)] -contains 'trinity.actual.battle.net'
    })
    if ($active.Count) {
        if (@($active | Where-Object { $_ -notmatch '^\s*127\.0\.0\.1\s' }).Count) {
            throw 'An existing hosts entry points trinity.actual.battle.net elsewhere. Preserved it; inspect before changing.'
        }
        Write-Output 'An existing loopback portal entry already works; preserved it.'
        return
    }
    $backup = Join-Path $private 'hosts-before-forever.bin'
    if (!(Test-Path -LiteralPath $backup)) { [IO.File]::WriteAllBytes($backup, $original) }
    $append = [Text.Encoding]::ASCII.GetBytes("`r`n$marker`r`n")
    $combined = New-Object byte[] ($original.Length + $append.Length)
    [Array]::Copy($original, 0, $combined, 0, $original.Length)
    [Array]::Copy($append, 0, $combined, $original.Length, $append.Length)
    [IO.File]::WriteAllBytes($hostsFile, $combined)
    Write-Output 'Added only: 127.0.0.1 trinity.actual.battle.net (tagged for undo).'
    return
}
if ($Undo) {
    $thumbFile = Join-Path $private 'ca-thumbprint.txt'
    if (Test-Path -LiteralPath $thumbFile) {
        $thumb = (Get-Content -LiteralPath $thumbFile -Raw).Trim()
        $certPath = "Cert:\CurrentUser\Root\$thumb"
        if (Test-Path -LiteralPath $certPath) { Remove-Item -LiteralPath $certPath }
        Write-Output "Removed this installation CA from CurrentUser Root: $thumb"
    }
    return
}
New-Item -ItemType Directory -Path $certs -Force | Out-Null
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
function OpenSsl([string[]]$Arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $openssl @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code) { throw "OpenSSL failed: $output" }
}
Push-Location $certs
try {
    if (!(Test-Path -LiteralPath '.\chain.pem')) {
        @"
[req]
distinguished_name=dn
x509_extensions=ca
prompt=no
[dn]
CN=Forever aleksanderG Local CA $env:COMPUTERNAME
[ca]
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
nameConstraints=critical,permitted;DNS:actual.battle.net
"@ | Set-Content -LiteralPath '.\ca.cnf' -Encoding ASCII
        @'
[req]
distinguished_name=dn
prompt=no
[dn]
CN=trinity.actual.battle.net
'@ | Set-Content -LiteralPath '.\server.cnf' -Encoding ASCII
        @'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
subjectAltName=DNS:trinity.actual.battle.net
extendedKeyUsage=serverAuth
authorityKeyIdentifier=keyid:always
'@ | Set-Content -LiteralPath '.\leaf.ext' -Encoding ASCII
        OpenSsl @('req','-x509','-newkey','rsa:3072','-nodes','-keyout','ca.key','-out','ca.pem','-days','825','-config','ca.cnf')
        OpenSsl @('req','-new','-newkey','rsa:2048','-nodes','-keyout','server.key','-out','server.csr','-config','server.cnf')
        OpenSsl @('x509','-req','-in','server.csr','-CA','ca.pem','-CAkey','ca.key','-CAcreateserial','-out','server.pem','-days','365','-extfile','leaf.ext')
        (Get-Content -LiteralPath '.\server.pem','.\ca.pem') | Set-Content -LiteralPath '.\chain.pem' -Encoding ASCII
    }
    OpenSsl @('verify','-CAfile','ca.pem','-verify_hostname','trinity.actual.battle.net','server.pem')
    $imported = Import-Certificate -FilePath "$certs\ca.pem" -CertStoreLocation Cert:\CurrentUser\Root
    $imported.Thumbprint | Set-Content -LiteralPath (Join-Path $private 'ca-thumbprint.txt') -Encoding ASCII
    Write-Output "Trusted this installation name-constrained CA in CurrentUser Root: $($imported.Thumbprint)"
} finally { Pop-Location }
