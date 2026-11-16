# Compatibility entry point; complete integration now covers Start, Stop and Restart.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\Install-LauncherIntegration.ps1"
