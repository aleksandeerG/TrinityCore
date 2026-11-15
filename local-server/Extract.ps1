[CmdletBinding()]
param([string]$Client = 'F:\Games\World of Warcraft', [int]$Threads = 6)
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$root = Split-Path $source -Parent
$output = [IO.Path]::GetFullPath((Join-Path $root 'server'))
if (!$output.StartsWith([IO.Path]::GetFullPath($root) + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Extractor output must remain inside this workspace.'
}
# The upstream resume script removes only its intermediate Buildings and dir_bin folders beneath this checked output.
& "$source\tools\extract_client_data.ps1" -ClientPath $Client -OutputPath $output -Threads $Threads -Builds 70938,70888,70862 -Resume
if ($LASTEXITCODE) { throw 'Data extraction failed. Inspect the log; do not mark incomplete data ready.' }
