# Register this installed source build with the verified standalone launcher.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$launcherRoot = Join-Path $root 'tools'
$launcher = Join-Path $launcherRoot 'WoWForeverLauncher.exe'
if (!(Test-Path -LiteralPath $launcher)) { throw 'The verified standalone launcher is missing.' }
foreach ($relative in @('server\worldserver.exe','server\worldserver.conf','server\bnetserver.conf','local\my.ini','local\certs\profile.json')) {
    if (!(Test-Path -LiteralPath (Join-Path $root $relative))) { throw "Source server installation is incomplete: $relative" }
}
$encoding = New-Object Text.UTF8Encoding($false)
function Write-Managed([string]$Path, [string]$Text, [string[]]$AcceptedMarkers) {
    if (Test-Path -LiteralPath $Path) {
        $current = [IO.File]::ReadAllText($Path)
        if ($current -eq $Text) { return }
        $managed = $false
        foreach ($marker in $AcceptedMarkers) { if ($current.StartsWith($marker)) { $managed = $true; break } }
        if (!$managed) { throw "An unmanaged launcher file was preserved without replacement: $Path" }
    }
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}
$marker = '# forever-source-build-launcher-adapter-v1'
$template = @'
# forever-source-build-launcher-adapter-v1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$control = Join-Path $workspaceRoot 'source\local-server\launcher_control.py'
if (!(Test-Path -LiteralPath $control)) { throw 'The source-built server lifecycle adapter is missing.' }
& python $control __ACTION__
if ($LASTEXITCODE) { exit $LASTEXITCODE }
'@
foreach ($action in @('start','stop','restart')) {
    $text = $template.Replace('__ACTION__',$action)
    $parseErrors = $null
    $tokens = $null
    [Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors) { throw 'Generated lifecycle adapter failed PowerShell parsing.' }
    $name = (Get-Culture).TextInfo.ToTitleCase($action) + '-WoWForever.ps1'
    Write-Managed (Join-Path $launcherRoot "repack\$name") $text @($marker,'# forever-source-build-stop-adapter-v1')
}
# HasOwnServer only tests existence of this file; it does not parse its contents.
# Register the real completed installation without copying any credential into tools.
$installed = @'
# forever-source-build-installation-v1
Existing source-built WoW Forever server. No repack installation is required.
Game credentials: run source/local-server/Show-Login.ps1 from the workspace.
Updates and backups: use the source/local-server operating guide.
'@
Write-Managed (Join-Path $launcherRoot 'secrets\first-login.txt') $installed @('# forever-source-build-installation-v1')
$restart = '# forever-source-build-launcher-path-v1' + "`r`n" + (Join-Path $launcherRoot 'repack\Restart-WoWForever.ps1') + "`r`n"
Write-Managed (Join-Path $launcherRoot 'config\restart-script.txt') $restart @('# forever-source-build-launcher-path-v1')
$serverPath = '# forever-source-build-launcher-path-v1' + "`r`n" + (Join-Path $root 'server') + "`r`n"
Write-Managed (Join-Path $launcherRoot 'config\server-dir.txt') $serverPath @('# forever-source-build-launcher-path-v1')
Write-Output 'Launcher Start, Stop and Restart are connected to the existing source build. No credentials were copied.'
