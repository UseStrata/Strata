# build.ps1 - bootstrap the Strata compiler and build all artifacts into compiler\bin\ :
#     stratac.exe    front-end #1 (the compiler CLI: run, build, emit, check, ast, tokens)
#     console.exe    front-end #2 (the explorer console)
#     libstrata.dll  the compiler as a shared library (the exe/lib/LSP split in
#                    ARCHITECTURE.md sec 11)
#
# The compiler is written in Strata (src/), so building it needs a Strata compiler:
#
#   stage0  a PINNED released stratac (bootstrap.txt), downloaded once and cached
#   stage1  stage0 builds src/stratac.strata
#   stage2  stage1 builds src/stratac.strata  (the compiler, built by itself)
#
# Fixpoint check: stage1 and stage2 must emit byte-identical C for the compiler; if they
# don't, the build fails. stage2 is what ships. Run from anywhere:
#     powershell -ExecutionPolicy Bypass -File compiler\build.ps1
#     ... -Bootstrap C:\path\to\stratac.exe     use a specific stage0 instead
#     ... -WriteSeed                            also refresh seed/ (the portable C seed
#                                               that bootstraps macOS / Linux: build.sh)
#
# The stage0 rule: src/ may only use language features the pinned release supports.
# Before the compiler's own code uses a new feature, release a version that has it and
# bump bootstrap.txt to it.

param([string]$Bootstrap, [switch]$WriteSeed)

$ErrorActionPreference = "Stop"
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\compiler
$src      = Join-Path $here "src"
$lib      = Join-Path $here "lib"
$bin      = Join-Path $here "bin"
$boot     = Join-Path $here "build"      # stage compilers (a sibling of lib/, so they find it)

foreach ($d in $bin, $boot) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

# --- stage0: the pinned bootstrap compiler -----------------------------------
$pin    = (Get-Content (Join-Path $here "bootstrap.txt") -Raw).Trim()   # e.g. "1.1.0"
$stage0 = $Bootstrap
if (-not $stage0) {
    $cache  = Join-Path $boot "bootstrap-$pin"
    $stage0 = Join-Path $cache "strata\stratac.exe"
    if (-not (Test-Path $stage0)) {
        $url = "https://github.com/UseStrata/Strata/releases/download/v$pin/strata-$pin-windows-x64.zip"
        $zip = Join-Path $boot "bootstrap-$pin.zip"
        Write-Host "downloading bootstrap compiler v$pin ..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $cache -Force
            Remove-Item $zip
        } catch {
            # offline: fall back to an installed stratac (the fixpoint check still guards the result)
            $installed = (Get-Command stratac -ErrorAction SilentlyContinue).Source
            if (-not $installed) { throw "cannot download $url and no stratac on PATH; pass -Bootstrap <stratac.exe>" }
            Write-Host "download failed; using installed $installed as stage0" -ForegroundColor Yellow
            $stage0 = $installed
        }
    }
}
if (-not (Test-Path $stage0)) { throw "bootstrap compiler not found: $stage0" }
Write-Host "stage0: $(& $stage0 version)" -ForegroundColor Cyan

$compilerSrc = Join-Path $src "stratac.strata"
$builtExe    = Join-Path $src "stratac.exe"    # `stratac build` writes next to the source

# Build src/stratac.strata with compiler $with; copy the result to $to.
# (Each stage runs from its own copy, so it never overwrites the exe that is running.)
function Build-Stage([string]$name, [string]$with, [string]$to) {
    Write-Host "building $name ..." -ForegroundColor Cyan
    & $with build $compilerSrc | Out-Null
    if (-not $?) { throw "$name build failed" }
    Copy-Item $builtExe $to -Force
}

# --- stage1, stage2: the compiler, built by stage0 and then by itself --------
$stage1 = Join-Path $boot "stage1.exe"
$stage2 = Join-Path $boot "stage2.exe"
Build-Stage "stage1 (built by stage0)" $stage0 $stage1
Build-Stage "stage2 (built by stage1)" $stage1 $stage2

# --- fixpoint: stage1 and stage2 must generate the same compiler -------------
$c1 = (& $stage1 emit $compilerSrc) -join "`n"
$c2 = (& $stage2 emit $compilerSrc) -join "`n"
if ($c1 -ne $c2) { throw "fixpoint check FAILED: stage1 and stage2 emit different C for the compiler" }
Write-Host "fixpoint ok: stage1 and stage2 emit identical C" -ForegroundColor Green

Copy-Item $stage2 (Join-Path $bin "stratac.exe") -Force
$stratac = Join-Path $bin "stratac.exe"

# --- the seed: this compiler as portable C, for bootstrapping other platforms ----
# src\stratac.c is stage1's output for the compiler (= stage2's, by the fixpoint), written
# by stratac itself (LF, byte-exact). Kept with the headers it was generated against, so
# build.sh can compile it however src/ and lib/ change later. See seed/README.md.
if ($WriteSeed) {
    $seed = Join-Path $here "seed"
    foreach ($d in $seed, (Join-Path $seed "src"), (Join-Path $seed "lib")) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    Copy-Item (Join-Path $src "stratac.c") (Join-Path $seed "stratac.c") -Force
    Copy-Item (Join-Path $src "strata_host.h") (Join-Path $seed "src\strata_host.h") -Force
    Remove-Item (Join-Path $seed "lib\*.h") -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $lib "*.h") (Join-Path $seed "lib") -Force
    $ver = [regex]::Match((Get-Content (Join-Path $src "version.strata") -Raw), 'return "([0-9][0-9.]*)').Groups[1].Value
    [IO.File]::WriteAllText((Join-Path $seed "VERSION"), "$ver`n")
    Write-Host "wrote seed\ (stratac $ver)" -ForegroundColor Green
}

# --- console.exe: built by the shipped compiler ------------------------------
Write-Host "building console.exe ..." -ForegroundColor Cyan
& $stratac build (Join-Path $src "console.strata") | Out-Null
if (-not $?) { throw "console.exe build failed" }
Copy-Item (Join-Path $src "console.exe") (Join-Path $bin "console.exe") -Force

# --- libstrata.dll: the compiler as a library (api/strata.toml -> bin/) -----
# Its public API is src/libstrata.strata (documented for C in api/strata.h). The build
# also writes bin/libstrata.dll.a (import library) and bin/libstrata.h (generated header).
Write-Host "building libstrata.dll ..." -ForegroundColor Cyan
& $stratac build (Join-Path $here "api") | Out-Null
if (-not $?) { throw "libstrata.dll build failed" }

# --- lib/srt.o: the native backend's runtime ----------------------------------
# Written in Strata (lib/srt.strata) and compiled by the compiler just built, with its own
# native backend; Strata's linker (src/pelink.strata) links it into native programs.
Write-Host "building lib\srt.o ..." -ForegroundColor Cyan
& $stratac object (Join-Path $lib "srt.strata") (Join-Path $lib "srt.o")
if ($LASTEXITCODE -ne 0) { throw "lib\srt.o build failed" }

Write-Host ""
Write-Host "artifacts in compiler\bin\ :" -ForegroundColor Green
Get-ChildItem (Join-Path $bin '*') -Include *.exe,*.dll | ForEach-Object { "  {0,-16} {1,8:N0} bytes" -f $_.Name, $_.Length }
