# package.ps1 - build a distributable Strata toolchain archive for a GitHub Release.
# Produces compiler\dist\strata-<version>-windows-x64.zip containing the compiler, the
# runtime it needs, and the licenses - the layout install.ps1 expects (stratac finds its
# lib/ next to the exe). A future installer can download and unzip this.
#
#   powershell -ExecutionPolicy Bypass -File compiler\package.ps1 -Version 0.10.0
#   gh release upload v0.10.0 compiler\dist\strata-0.10.0-windows-x64.zip

param([string]$Version = "dev")

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\compiler
$repo = Split-Path -Parent $here
$bin  = Join-Path $here 'bin'
$lib  = Join-Path $here 'lib'
$dist = Join-Path $here 'dist'

# 1. build fresh binaries
Write-Host "building ..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'build.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) { throw "build failed" }

# 2. stage the toolchain (flat layout: exe at root, runtime in lib\)
$stageRoot = Join-Path $env:TEMP "strata-pkg"
if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
$stage = Join-Path $stageRoot "strata"
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'lib') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'include') | Out-Null
foreach ($f in 'stratac.exe','console.exe','libstrata.dll','libstrata.dll.a','libstrata.lib') { Copy-Item (Join-Path $bin $f) (Join-Path $stage $f) }
Copy-Item (Join-Path $lib '*.h') (Join-Path $stage 'lib')
Copy-Item (Join-Path $lib 'srt.strata') (Join-Path $stage 'lib')   # the native backend's runtime (Strata)
Copy-Item (Join-Path $lib 'CrossPlatform.strata') (Join-Path $stage 'lib')   # Strata's libraries (import CrossPlatform)
Copy-Item (Join-Path $lib 'CrossPlatform') (Join-Path $stage 'lib') -Recurse
Copy-Item (Join-Path $lib 'srt.o') (Join-Path $stage 'lib')   # ... compiled: Strata's linker links it
# the embedding API: C header, C++ wrapper, C# bindings
foreach ($f in 'strata.h','strata.hpp','Strata.cs') { Copy-Item (Join-Path $here "api\$f") (Join-Path $stage "include\$f") }
foreach ($f in 'LICENSE','LICENSE-RUNTIME.md','LICENSE-EMBEDDING.md','README.md','CHANGELOG.md') {
    if (Test-Path (Join-Path $repo $f)) { Copy-Item (Join-Path $repo $f) (Join-Path $stage $f) }
}

# 3. zip it
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "strata-$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip

Write-Host ""
Write-Host "packaged: $zip" -ForegroundColor Green
Write-Host "note: native builds need no C compiler (Strata compiles, assembles and links them);"
Write-Host "      the C backend (programs importing C headers, other platforms) uses gcc / cc."
