[CmdletBinding()]
param([int]$Jobs = 6, [switch]$PreviewOnly)
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$root = Split-Path $source -Parent
function Git([string[]]$Arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & git.exe -C $source @Arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($code) { throw "Git failed (code $code): $output" }
    $output
}
if ((Git @('branch','--show-current')) -ne 'aleksanderG') { throw 'Switch to aleksanderG before updating.' }
if (Git @('status','--porcelain')) { throw 'Commit or stash all changes, including untracked files, before updating.' }
Git @('fetch','upstream','forever-bots')
Write-Output 'Commits to integrate from upstream/forever-bots:'
Git @('log','--oneline','HEAD..upstream/forever-bots')
Git @('diff','--stat','HEAD...upstream/forever-bots')
if ($PreviewOnly) { return }
$mergeBase = Git @('merge-base','HEAD','upstream/forever-bots')
$upstreamHead = Git @('rev-parse','upstream/forever-bots')
if ($mergeBase -eq $upstreamHead) { Write-Output 'This branch already includes upstream/forever-bots.'; return }
# The full pre-migration backup contains all five DBs, configs, secrets and the old installed executables.
& python "$PSScriptRoot\manage.py" backup
if ($LASTEXITCODE) { throw 'Backup failed. Nothing has been merged or deployed.' }
try { Git @('merge','--no-edit','upstream/forever-bots') }
catch { throw "Merge stopped. Resolve the conflicts or run git merge --abort. The server remains stopped and its installed binaries are unchanged. $_" }
# Keep the clean reference branch at the upstream commit, but never discard local commits placed there by hand.
$reference = Git @('rev-parse','forever-bots')
$referenceBase = Git @('merge-base','forever-bots','upstream/forever-bots')
if ($reference -eq $referenceBase) { Git @('branch','-f','forever-bots','upstream/forever-bots') }
& "$PSScriptRoot\Build.ps1" -Jobs $Jobs
& "$PSScriptRoot\Prepare-Client.ps1"
& python "$PSScriptRoot\manage.py" start
if ($LASTEXITCODE) { throw 'Updated source built, but server start failed. See the backup and logs.' }
# Auth/core sql/custom and bot sql/playerbot_v2 migrations run from SourceDirectory on startup.
$ready = $false
$deadline = (Get-Date).AddMinutes(30)
while ((Get-Date) -lt $deadline) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & python "$PSScriptRoot\manage.py" check *> "$root\inspection\update-startup-check.log"
    $checkCode = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($checkCode -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 5
}
if (!$ready) { throw 'Startup did not pass within 30 minutes. Keep the matching pre-update DB backup; see logs.' }
Write-Output 'Update started and passed server checks. Review logs and verify login/save/reconnect before pushing the merge.'
Write-Output 'Push when satisfied: git -C source push origin aleksanderG'
