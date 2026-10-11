# package.ps1 - build the distributable Strata toolchain archives for a GitHub Release:
#   compiler\dist\strata-<version>-windows-x64.zip       (the layout install.ps1 expects)
#   compiler\dist\strata-<version>-linux-x64.tar.gz      \ cross-compiled here: CI checks these
#   compiler\dist\strata-<version>-macos-arm64.tar.gz    / compilers equal the ones those OSes build
# each with the compiler, the runtime it needs, and the licenses (stratac finds its lib/
# next to itself).
#
#   powershell -ExecutionPolicy Bypass -File compiler\package.ps1 -Version 0.10.0
#   gh release upload v0.10.0 compiler\dist\strata-0.10.0-*

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
Copy-Item (Join-Path $lib 'srt') (Join-Path $stage 'lib') -Recurse   # the runtime's OS layers
Copy-Item (Join-Path $lib 'srt.o') (Join-Path $stage 'lib')   # ... compiled: Strata's linker links it
Copy-Item (Join-Path $lib 'srt-linux-x64.o') (Join-Path $stage 'lib')   # the Linux runtime (cross-compiling: --target linux-x64)
Copy-Item (Join-Path $lib 'srt-macos-arm64.o') (Join-Path $stage 'lib')   # the macOS runtime (--target macos-arm64)
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

Write-Host "packaged: $zip" -ForegroundColor Green

# 4. Linux and macOS: the same toolchain, cross-compiled, as .tar.gz (executables 0755)
function Write-TarGz([string]$root, [string]$top, [string]$out, [string[]]$exec) {
    # a ustar archive of $root's tree under the name $top, gzipped
    $ms = New-Object IO.MemoryStream
    function Put-Header([string]$name, [long]$size, [string]$mode, [char]$type) {
        $h = New-Object byte[] 512
        $enc = [Text.Encoding]::ASCII
        $nb = $enc.GetBytes($name)
        if ($nb.Length -gt 100) { throw "path too long for the archive: $name" }
        [Array]::Copy($nb, 0, $h, 0, $nb.Length)
        $put = { param($text, $at) $b = $enc.GetBytes($text); [Array]::Copy($b, 0, $h, $at, $b.Length) }
        & $put ($mode + "`0") 100
        & $put "0000000`0" 108
        & $put "0000000`0" 116
        & $put ([Convert]::ToString($size, 8).PadLeft(11, '0') + "`0") 124
        & $put ([Convert]::ToString([long]1760000000, 8).PadLeft(11, '0') + "`0") 136
        & $put "        " 148
        $h[156] = [byte][char]$type
        & $put "ustar`0" 257
        & $put "00" 263
        $sum = 0
        foreach ($x in $h) { $sum += $x }
        & $put ([Convert]::ToString($sum, 8).PadLeft(6, '0') + "`0 ") 148
        $ms.Write($h, 0, 512)
    }
    Put-Header "$top/" 0 "0000755" '5'
    $base = (Resolve-Path $root).Path.TrimEnd('\')
    foreach ($item in (Get-ChildItem $root -Recurse | Sort-Object FullName)) {
        $rel = $item.FullName.Substring($base.Length + 1).Replace('\', '/')
        if ($item.PSIsContainer) { Put-Header "$top/$rel/" 0 "0000755" '5'; continue }
        $bytes = [IO.File]::ReadAllBytes($item.FullName)
        $mode = "0000644"
        if ($exec -contains $rel) { $mode = "0000755" }
        Put-Header "$top/$rel" $bytes.Length $mode '0'
        $ms.Write($bytes, 0, $bytes.Length)
        $pad = (512 - ($bytes.Length % 512)) % 512
        if ($pad -gt 0) { $ms.Write((New-Object byte[] $pad), 0, $pad) }
    }
    $ms.Write((New-Object byte[] 1024), 0, 1024)
    $fs = [IO.File]::Create($out)
    $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Compress)
    $ms.Position = 0
    $ms.CopyTo($gz)
    $gz.Close(); $fs.Close()
}
$stratac = Join-Path $bin 'stratac.exe'
foreach ($target in 'linux-x64', 'macos-arm64') {
    $dll = 'libstrata.so'
    if ($target -eq 'macos-arm64') { $dll = 'libstrata.dylib' }
    $pstage = Join-Path $stageRoot "strata-$target"
    New-Item -ItemType Directory -Force -Path (Join-Path $pstage 'lib') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $pstage 'include') | Out-Null
    foreach ($prog in 'stratac', 'console') {
        & $stratac build (Join-Path $here "src\$prog.strata") --target $target --force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$prog for $target failed to build" }
        Move-Item (Join-Path $here "src\$prog") (Join-Path $pstage $prog) -Force
    }
    & $stratac build (Join-Path $here 'api') --target $target --force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "libstrata for $target failed to build" }
    Move-Item (Join-Path $bin $dll) (Join-Path $pstage $dll) -Force
    Copy-Item (Join-Path $lib '*.h') (Join-Path $pstage 'lib')
    foreach ($f in 'srt.strata', 'CrossPlatform.strata', 'srt.o', 'srt-linux-x64.o', 'srt-macos-arm64.o') { Copy-Item (Join-Path $lib $f) (Join-Path $pstage 'lib') }
    Copy-Item (Join-Path $lib 'CrossPlatform') (Join-Path $pstage 'lib') -Recurse
    Copy-Item (Join-Path $lib 'srt') (Join-Path $pstage 'lib') -Recurse
    foreach ($f in 'strata.h','strata.hpp','Strata.cs') { Copy-Item (Join-Path $here "api\$f") (Join-Path $pstage "include\$f") }
    foreach ($f in 'LICENSE','LICENSE-RUNTIME.md','LICENSE-EMBEDDING.md','README.md','CHANGELOG.md') {
        if (Test-Path (Join-Path $repo $f)) { Copy-Item (Join-Path $repo $f) (Join-Path $pstage $f) }
    }
    $tgz = Join-Path $dist "strata-$Version-$target.tar.gz"
    Write-TarGz $pstage "strata" $tgz @('stratac', 'console')
    Write-Host "packaged: $tgz" -ForegroundColor Green
}

Write-Host ""
Write-Host "note: native builds need no C compiler (Strata compiles, assembles and links them)."
