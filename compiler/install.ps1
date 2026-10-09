# install.ps1 - install (or update) the Strata toolchain into one shared location,
# the way a C compiler lives on a system: the `strata` executable(s) + the `lib/`
# runtime, added to PATH so `strata` works from any directory. Mirrors D--'s install.
# Re-run any time to update.
#
#   powershell -ExecutionPolicy Bypass -File install.ps1              # per-user (no admin)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -System      # all users (elevates)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Prefix D:\tools\strata
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#
# Installed layout:  <prefix>\stratac.exe  <prefix>\console.exe  <prefix>\libstrata.dll(.a / .lib)
#                    <prefix>\lib\...       the runtime headers
#                    <prefix>\include\...   the embedding API (strata.h, strata.hpp, Strata.cs)
# stratac finds its lib/ next to the exe, so nothing else needs configuring.

param(
    [string]$Prefix,
    [switch]$System,
    [switch]$Uninstall,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$compiler = $PSScriptRoot
$bin      = Join-Path $compiler 'bin'
$libSrc   = Join-Path $compiler 'lib'

# --- Resolve prefix + PATH scope --------------------------------------------
if ($System) {
    if (-not $Prefix) { $Prefix = Join-Path $env:ProgramFiles 'strata' }
    $scope = 'Machine'
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent() `
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Requesting administrator rights (approve the UAC prompt)..."
        $argl = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-System')
        if ($Prefix)    { $argl += @('-Prefix',"`"$Prefix`"") }
        if ($Uninstall) { $argl += '-Uninstall' }
        if ($NoBuild)   { $argl += '-NoBuild' }
        Start-Process powershell -Verb RunAs -ArgumentList $argl
        exit
    }
} else {
    if (-not $Prefix) { $Prefix = Join-Path $env:LOCALAPPDATA 'Programs\strata' }
    $scope = 'User'
}

function Remove-FromPath($dir, $scope) {
    $path = [Environment]::GetEnvironmentVariable('Path', $scope)
    if (-not $path) { return }
    $parts = $path -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $dir.TrimEnd('\')) }
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), $scope)
}

# --- Uninstall --------------------------------------------------------------
if ($Uninstall) {
    if (Test-Path $Prefix) { Remove-Item $Prefix -Recurse -Force; Write-Host "removed $Prefix" }
    Remove-FromPath $Prefix $scope
    Write-Host "removed $Prefix from $scope PATH"
    Write-Host "Done. Restart your terminal for PATH to update."
    return
}

# --- Build the artifacts (unless -NoBuild) ----------------------------------
if (-not $NoBuild -and (Test-Path (Join-Path $compiler 'build.ps1'))) {
    Write-Host "building artifacts via build.ps1 ..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $compiler 'build.ps1')
    if ($LASTEXITCODE -ne 0) { throw "build.ps1 failed" }
}
$exe = Join-Path $bin 'stratac.exe'
if (-not (Test-Path $exe)) { throw "stratac.exe not found in bin\; run build.ps1 first" }

# --- Copy into the shared location ------------------------------------------
Write-Host "installing to $Prefix ..."
New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
foreach ($a in @('stratac.exe','console.exe','libstrata.dll','libstrata.dll.a','libstrata.lib')) {
    $srcA = Join-Path $bin $a
    if (Test-Path $srcA) { Copy-Item $srcA (Join-Path $Prefix $a) -Force }
}

# the embedding API, for engines/tools that link libstrata
$incDst = Join-Path $Prefix 'include'
New-Item -ItemType Directory -Force -Path $incDst | Out-Null
foreach ($f in @('strata.h','strata.hpp','Strata.cs')) {
    $srcF = Join-Path $compiler "api\$f"
    if (Test-Path $srcF) { Copy-Item $srcF (Join-Path $incDst $f) -Force }
}

$libDst = Join-Path $Prefix 'lib'
if (Test-Path $libDst) { Remove-Item $libDst -Recurse -Force }   # drop stale runtime files
if (Test-Path $libSrc) { Copy-Item $libSrc $libDst -Recurse -Force }
else { New-Item -ItemType Directory -Force -Path $libDst | Out-Null }

# --- Add to PATH (idempotent) ----------------------------------------------
$path = [Environment]::GetEnvironmentVariable('Path', $scope)
if (-not $path) { $path = '' }
$onPath = ($path -split ';') | Where-Object { $_.TrimEnd('\') -eq $Prefix.TrimEnd('\') }
if (-not $onPath) {
    [Environment]::SetEnvironmentVariable('Path', ($path.TrimEnd(';') + ';' + $Prefix), $scope)
    Write-Host "added $Prefix to $scope PATH"
} else {
    Write-Host "$Prefix already on $scope PATH"
}

# --- Report -----------------------------------------------------------------
Write-Host ""
Write-Host "installed: $(Join-Path $Prefix 'stratac.exe')"
Write-Host "runtime:   $libDst"
if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "NOTE: release builds use the C compiler 'gcc', not on PATH." -ForegroundColor Yellow
    Write-Host "      Install MinGW/MSYS2 gcc for 'strata build' (bundled tcc will cover 'strata run')." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Done. Open a NEW terminal, then:  stratac run <file.strata>"
