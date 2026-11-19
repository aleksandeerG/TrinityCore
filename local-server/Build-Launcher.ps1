[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The Windows .NET Framework C# compiler is missing.'
}

$tools = Join-Path $root 'tools'
$null = New-Item -ItemType Directory -Path $tools -Force
$output = Join-Path $tools 'WoWForeverLocal.exe'
$sourceFiles = @('ForeverLocalLauncher.cs', 'RealmConnection.cs', 'ClientLoginKey.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }

& $compiler /nologo /target:winexe /platform:x64 /optimize+ /warnaserror+ "/out:$output" `
    /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll $sourceFiles
if ($LASTEXITCODE -ne 0) { throw "Launcher compilation failed (exit code $LASTEXITCODE)." }
Write-Output $output
