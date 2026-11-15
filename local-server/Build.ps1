[CmdletBinding()]
param([int]$Jobs = 6, [switch]$ConfigureOnly, [switch]$Fresh)
$ErrorActionPreference = 'Stop'
function Invoke-Native([string]$File, [string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue' # Windows PowerShell 5.1 labels native stderr as errors even on success.
    & $File @Arguments
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    if ($code -ne 0) { throw "$File exited with code $code" }
}
$source = Split-Path $PSScriptRoot -Parent
$root = Split-Path $source -Parent
# Static scripts have hundreds of include directories: a short alias avoids Windows' 32767-character process limit.
# Reuse only an alias that resolves to this exact workspace; never replace another drive mapping.
$shortRoot = $null
$aliases = @(& subst.exe)
foreach ($letter in @('W','V','U','R','Q')) {
    $entry = @($aliases | Where-Object { $_ -like "${letter}:\: => *" })
    if ($entry.Count -and ($entry[0] -replace '^[A-Z]:\\: => ', '') -eq $root) { $shortRoot = "${letter}:\"; break }
    if (!(Test-Path -LiteralPath "${letter}:\")) {
        & subst.exe "${letter}:" $root
        if ($LASTEXITCODE) { throw 'Could not create the short build drive alias.' }
        $shortRoot = "${letter}:\"
        break
    }
}
if (!$shortRoot) { throw 'No free short build drive among W,V,U,R,Q.' }
$shortSource = Join-Path $shortRoot 'source'
$build = Join-Path $shortRoot 'build'
Write-Output "Build path alias: $shortRoot -> $root (no files moved)."
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio 2022 C++ tools are required.' }
$cmake = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$ninja = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
if (!(Test-Path -LiteralPath $cmake)) { throw 'Install the Visual Studio C++ CMake tools component.' }
# Read the compiler environment from the vendor batch file. No filesystem mutations cross shells.
$devcmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
$env:PATH = (Split-Path $vswhere -Parent) + ';' + $env:PATH
$envProcess = New-Object System.Diagnostics.ProcessStartInfo
$envProcess.FileName = $env:ComSpec
$envProcess.Arguments = '/d /s /c ""' + $devcmd + '" -no_logo -arch=x64 -host_arch=x64 >nul && set"'
$envProcess.UseShellExecute = $false
$envProcess.CreateNoWindow = $true
$envProcess.RedirectStandardOutput = $true
$compilerEnvironment = [System.Diagnostics.Process]::Start($envProcess)
$environment = $compilerEnvironment.StandardOutput.ReadToEnd() -split "`r?`n"
$compilerEnvironment.WaitForExit()
if ($compilerEnvironment.ExitCode -ne 0) { throw 'Loading the Visual Studio compiler environment failed.' }
foreach ($line in $environment) {
    if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
$mysql = Join-Path $shortRoot 'dependencies\mysql\mysql-8.4.7-winx64'
$vcpkg = Join-Path $shortRoot 'dependencies\vcpkg'
$openssl = Join-Path $vcpkg 'installed\x64-windows'
$env:PATH = "$openssl\bin;$mysql\lib;$mysql\bin;$env:PATH"
$env:VCPKG_DISABLE_METRICS = '1'
$argsConfigure = @('-S', $shortSource, '-B', $build, '-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$ninja",
    '-DCMAKE_BUILD_TYPE=RelWithDebInfo', "-DCMAKE_TOOLCHAIN_FILE=$vcpkg\scripts\buildsystems\vcpkg.cmake",
    '-DVCPKG_TARGET_TRIPLET=x64-windows-static-md', "-DMYSQL_ROOT_DIR=$mysql", "-DCMAKE_INSTALL_PREFIX=$root\server",
    '-DSERVERS=1', '-DTOOLS=1', '-DSCRIPTS=static', '-DBUILD_PLAYERBOT_V2=1', '-DBUILD_TESTING=1', '-DOPENSSL_USE_STATIC_LIBS=FALSE',
    "-DOPENSSL_ROOT_DIR=$openssl", "-DOPENSSL_INCLUDE_DIR=$openssl\include", "-DOPENSSL_CRYPTO_LIBRARY=$openssl\lib\libcrypto.lib",
    "-DOPENSSL_SSL_LIBRARY=$openssl\lib\libssl.lib", "-DLIB_EAY_RELEASE=$openssl\lib\libcrypto.lib",
    "-DLIB_EAY_DEBUG=$openssl\debug\lib\libcrypto.lib", "-DSSL_EAY_RELEASE=$openssl\lib\libssl.lib",
    "-DSSL_EAY_DEBUG=$openssl\debug\lib\libssl.lib")
if ($Fresh) { $argsConfigure += '--fresh' }
Invoke-Native $cmake $argsConfigure
if ($ConfigureOnly) { return }
Invoke-Native $cmake @('--build', $build, '--parallel', $Jobs)
$env:PATH = "$mysql\lib;$mysql\bin;$root\build\bin\RelWithDebInfo;$env:PATH"
Invoke-Native "$root\build\bin\RelWithDebInfo\tests.exe" @('[QuestCollectionLoot]')
if ((Get-Process worldserver,bnetserver -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$root\server\*" })) {
    throw 'Stop this workspace server before installing the build.'
}
Invoke-Native $cmake @('--install', $build, '--config', 'RelWithDebInfo')
Copy-Item -LiteralPath "$mysql\lib\libmysql.dll" -Destination "$root\server" -Force
Get-ChildItem -LiteralPath "$mysql\bin" -Filter '*.dll' | Copy-Item -Destination "$root\server" -Force
Get-ChildItem -LiteralPath "$openssl\bin" -Filter '*.dll' | Copy-Item -Destination "$root\server" -Force
$commit = & git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not record source revision.' }
[ordered]@{ commit=$commit; builtUtc=[DateTime]::UtcNow.ToString('o'); botModule=$true; configuration='RelWithDebInfo' } |
    ConvertTo-Json | Set-Content -LiteralPath "$root\server\build-manifest.json" -Encoding UTF8
Write-Output "Installed bot-enabled source build $commit into $root\server"
