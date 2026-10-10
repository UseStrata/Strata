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
#   stage3  stage2 builds it again
#
# Every stage is built natively (Strata's own backend, assembler and linker: no C
# compiler, not even for libstrata.dll). Fixpoint check: stage2 and stage3 must
# be byte-identical executables; if they aren't, the build fails. stage3 ships. Run from
# anywhere:
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
$srtSrc      = Join-Path $lib "srt.strata"
$srtObj      = Join-Path $lib "srt.o"

# The compiler is built by Strata's own native backend, assembler and linker: no C
# compiler. Native programs link the runtime lib/srt.o (lib/srt.strata, which also has the
# compiler's host functions, src/host.strata), so each stage first compiles the runtime.

# Build src/stratac.strata natively with compiler $with; copy the result to $to.
# (Each stage runs from its own copy, so it never overwrites the exe that is running.)
function Build-Stage([string]$name, [string]$with, [string]$to) {
    Write-Host "building $name ..." -ForegroundColor Cyan
    & $with build $compilerSrc --backend native --force | Out-Null
    if (-not $?) { throw "$name build failed" }
    Copy-Item $builtExe $to -Force
}
# Compile lib/srt.strata with compiler $with into $to.
function Build-Runtime([string]$with, [string]$to) {
    & $with object $srtSrc $to
    if ($LASTEXITCODE -ne 0) { throw "lib\srt.o build failed ($with)" }
}
function Build-Runtime-For([string]$with, [string]$target, [string]$to) {
    & $with object $srtSrc $to --target $target
    if ($LASTEXITCODE -ne 0) { throw "the $target runtime build failed" }
}

# --- stage1: built by stage0, with stage0's own runtime ---------------------------
# (the pinned release's lib/srt.o: it has everything the compiler's source calls, so
# today's lib/srt.strata is first compiled by stage1 - and may use what stage0 can't read)
$stage1 = Join-Path $boot "stage1.exe"
$stage2 = Join-Path $boot "stage2.exe"
$stage3 = Join-Path $boot "stage3.exe"
Build-Stage "stage1 (built by stage0)" $stage0 $stage1

# --- stage2, stage3: the compiler built by itself, twice ---------------------------
Build-Runtime $stage1 $srtObj
Build-Stage "stage2 (built by stage1)" $stage1 $stage2
$srt2 = Join-Path $boot "srt2.o"
Copy-Item $srtObj $srt2 -Force
Build-Runtime $stage2 $srtObj
Build-Stage "stage3 (built by stage2)" $stage2 $stage3

# --- fixpoint: stage2 and stage3 must be the same program, byte for byte -------------
# (and the runtime they compiled the same object file)
if ((Get-FileHash $srt2).Hash -ne (Get-FileHash $srtObj).Hash) { throw "fixpoint check FAILED: stage1 and stage2 compile lib\srt.strata differently" }
if ((Get-FileHash $stage2).Hash -ne (Get-FileHash $stage3).Hash) { throw "fixpoint check FAILED: stage2 and stage3 differ" }
Write-Host "fixpoint ok: stage2 and stage3 are identical" -ForegroundColor Green

Copy-Item $stage3 (Join-Path $bin "stratac.exe") -Force
$stratac = Join-Path $bin "stratac.exe"

# --- the runtime for the other native targets (cross-compiling: --target linux-x64 / macos-arm64) ---
Build-Runtime-For $stratac "linux-x64" (Join-Path $lib "srt-linux-x64.o")
Build-Runtime-For $stratac "macos-arm64" (Join-Path $lib "srt-macos-arm64.o")

# --- the seed: this compiler as portable C, for bootstrapping other platforms ----
# The C the compiler generates for itself, written by stratac (LF, byte-exact). Kept with
# the headers it was generated against, so build.sh can compile it however src/ and lib/
# change later. See seed/README.md.
if ($WriteSeed) {
    $seed = Join-Path $here "seed"
    foreach ($d in $seed, (Join-Path $seed "src"), (Join-Path $seed "lib")) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    & $stratac emit $compilerSrc (Join-Path $seed "stratac.c")
    if ($LASTEXITCODE -ne 0) { throw "writing the seed failed" }
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
# Its public API is src/libstrata.strata (documented for C in api/strata.h). Built natively;
# the build also writes bin/libstrata.dll.a and bin/libstrata.lib (import libraries for GNU
# ld and MSVC) and bin/libstrata.h (generated header).
Write-Host "building libstrata.dll ..." -ForegroundColor Cyan
& $stratac build (Join-Path $here "api") --backend native --force | Out-Null
if (-not $?) { throw "libstrata.dll build failed" }

Write-Host ""
Write-Host "artifacts in compiler\bin\ :" -ForegroundColor Green
Get-ChildItem (Join-Path $bin '*') -Include *.exe,*.dll | ForEach-Object { "  {0,-16} {1,8:N0} bytes" -f $_.Name, $_.Length }
