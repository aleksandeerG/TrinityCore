[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$checkout = Join-Path $root 'dependencies\vcpkg'
$baseline = '8f363bdc11359ede4bc51e5eb32a2617538049c8'
$current = & git -C $checkout rev-parse HEAD
if ($LASTEXITCODE -or $current -ne $baseline) { throw "Use the pinned microsoft/vcpkg checkout at $baseline. See README.md." }
$ports = @('filesystem','program-options','regex','locale','asio','beast','circular-buffer','dynamic-bitset',
    'multi-index','property-tree','signals2','uuid','iostreams','accumulators','dll','graph','heap','math','outcome','stacktrace','process')
$packages = @($ports | ForEach-Object { "boost-${_}:x64-windows-static-md" }) + @('openssl:x64-windows')
$env:VCPKG_DISABLE_METRICS = '1'
$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& "$checkout\vcpkg.exe" install @packages
$code = $LASTEXITCODE
$ErrorActionPreference = $old
if ($code) { throw "Dependency build failed (code $code)." }
