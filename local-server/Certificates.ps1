[CmdletBinding()]
param([switch]$HostsOnly, [switch]$Undo, [switch]$GenerateOnly, [switch]$Rotate)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$private = Join-Path $root 'local'
$certs = Join-Path $private 'certs'
$hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$marker = '127.0.0.1 trinity.actual.battle.net # forever-aleksanderG-local'
if (($GenerateOnly -or $Rotate) -and ($HostsOnly -or $Undo)) { throw 'Generation/rotation cannot be combined with hosts-only or undo.' }
if ($HostsOnly) {
    $original = if (Test-Path -LiteralPath $hostsFile) { [IO.File]::ReadAllBytes($hostsFile) } else { [byte[]]@() }
    # Latin-1 gives a reversible byte mapping, including existing non-UTF8 comments/BOMs.
    $hostsEncoding = [Text.Encoding]::GetEncoding(28591)
    $content = $hostsEncoding.GetString($original)
    if ($Undo) {
        # Remove only our exact line; preserve changes made by other software after setup.
        $escaped = [regex]::Escape($marker)
        $updated = [regex]::Replace($content, "(?m)^$escaped`r?`n|^$escaped$", '')
        if ($updated -ne $content) { [IO.File]::WriteAllBytes($hostsFile, $hostsEncoding.GetBytes($updated)) }
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
    $thumb = $null
    if (Test-Path -LiteralPath $thumbFile) { $thumb = (Get-Content -LiteralPath $thumbFile -Raw).Trim() }
    elseif (Test-Path -LiteralPath "$certs\ca.pem") {
        $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList "$certs\ca.pem"
        $thumb = $certificate.Thumbprint
    }
    if ($thumb) {
        $certPath = "Cert:\CurrentUser\Root\$thumb"
        if (Test-Path -LiteralPath $certPath) { Remove-Item -LiteralPath $certPath }
        Write-Output "Removed this installation CA from CurrentUser Root: $thumb"
    }
    return
}
if ($Rotate) {
    if (Get-Process bnetserver -ErrorAction SilentlyContinue) { throw 'Stop the login server before rotating certificates.' }
    if (Test-Path -LiteralPath "$certs\ca.pem") {
        $previous = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList "$certs\ca.pem"
        if ((Test-Path -LiteralPath "Cert:\CurrentUser\Root\$($previous.Thumbprint)") -or
            (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$($previous.Thumbprint)")) {
            throw 'Remove trust for the previous CA before rotating; -Undo removes this installation CurrentUser trust.'
        }
    }
}
$arguments = @("$PSScriptRoot\certificates.py")
if ($Rotate) { $arguments += '--rotate' }
& python @arguments
if ($LASTEXITCODE) { throw 'Certificate generation/profile validation failed; no trust was added.' }
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
    OpenSsl @('verify','-CAfile','ca.pem','-purpose','sslserver','-verify_hostname','trinity.actual.battle.net','server.pem')
    if ($GenerateOnly) { Write-Output 'Verified one-leaf certificates. Windows trust and hosts were not changed.'; return }
    $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList "$certs\ca.pem"
    $storePath = "Cert:\CurrentUser\Root\$($certificate.Thumbprint)"
    $imported = if (Test-Path -LiteralPath $storePath) { Get-Item -LiteralPath $storePath } else {
        Import-Certificate -FilePath "$certs\ca.pem" -CertStoreLocation Cert:\CurrentUser\Root
    }
    if (!(Test-Path -LiteralPath $storePath)) { throw 'Certificate trust was not installed; the Windows prompt may have been canceled.' }
    $imported.Thumbprint | Set-Content -LiteralPath (Join-Path $private 'ca-thumbprint.txt') -Encoding ASCII
    Write-Output "Trusted one-leaf CA in CurrentUser Root: $($imported.Thumbprint). No CA signing key is retained."
} finally { Pop-Location }
