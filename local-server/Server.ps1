[CmdletBinding()]
param(
    [ValidateSet('start','start-world','stop','status','backup','restore','command','create-account','check')][string]$Action = 'status',
    [string]$Argument,
    [switch]$ConfirmReplace
)
$ErrorActionPreference = 'Stop'
$arguments = @("$PSScriptRoot\manage.py", $Action)
if ($Argument) { $arguments += $Argument }
if ($ConfirmReplace) { $arguments += '--confirm-replace' }
& python @arguments
if ($LASTEXITCODE) { throw "Server action $Action failed (code $LASTEXITCODE)." }
