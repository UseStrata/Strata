# tests/run.ps1 - bootstrap the Strata compiler (build.ps1) and validate it:
#   1. the bootstrap: stage0 (pinned release) -> stage1 -> stage2 -> stage3, fixpoint-checked
#   2. goldens: each stage's output vs its golden file, byte-for-byte (ARCHITECTURE.md sec 6)
# Run from anywhere:
#     powershell -ExecutionPolicy Bypass -File compiler\tests\run.ps1
#
# A golden file  tests/<stage>/<name>.expected  is compared against the output of
#     stratac <stage> examples/<name>.strata
# using the SHIPPED compiler (bin\stratac.exe, the self-hosted stage3).
# Exit code 0 = all passed, 1 = a mismatch or build failure.

$ErrorActionPreference = "Stop"
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\compiler\tests
$compiler = Split-Path -Parent $here                          # ...\compiler
$src      = Join-Path $compiler "src"
$examples = Join-Path $compiler "examples"

# --- bootstrap (stage0 -> stage1 -> stage2 -> stage3, with the fixpoint check) ---
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $compiler "build.ps1") | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: bootstrap build failed (run compiler\build.ps1 to see why)" -ForegroundColor Red; exit 1 }
$strata = Join-Path $compiler "bin\stratac.exe"
Write-Host "PASS  bootstrap (pinned release -> stage1 -> stage2 -> stage3, native, fixpoint)" -ForegroundColor Green
$pass = 1; $fail = 0

# --- run each golden ---------------------------------------------------------
Get-ChildItem -Path $here -Directory | ForEach-Object {
    $stage = $_.Name                                          # e.g. "tokens"
    Get-ChildItem -Path $_.FullName -Filter *.expected | ForEach-Object {
        $name    = [IO.Path]::GetFileNameWithoutExtension($_.Name)
        $source  = Join-Path $examples "$name.strata"
        if (-not (Test-Path $source)) {
            Write-Host "SKIP  $stage/$name  (no examples\$name.strata)" -ForegroundColor Yellow
            return
        }
        # Normalize line endings (golden files may be CRLF; captured output is LF).
        $actual   = ((& $strata $stage $source) -join "`n") -replace "`r",""
        $expected = ((Get-Content $_.FullName -Raw) -replace "`r","").TrimEnd("`n")
        $actual   = $actual.TrimEnd("`n")
        if ($actual -eq $expected) {
            Write-Host "PASS  $stage/$name" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "FAIL  $stage/$name" -ForegroundColor Red
            $script:fail++
        }
    }
}

# --- projects (strata.toml): the build system ---------------------------------
# tests/projects/<name>/ is a project. If it has expected.txt, `stratac run <dir> --force`
# must print exactly that (a failing project's expected.txt holds its errors); otherwise
# `stratac build <dir> --force` must succeed (e.g. a dll). Then, for projects that built,
# a second `stratac build` must hit the cache ("up to date").
Get-ChildItem -Path (Join-Path $here "projects") -Directory | ForEach-Object {
    $dir = $_.FullName
    $name = $_.Name
    $expFile = Join-Path $dir "expected.txt"
    $ok = $true
    if (Test-Path $expFile) {
        $actual   = ((& $strata run $dir --force) -join "`n") -replace "`r",""
        $expected = ((Get-Content $expFile -Raw) -replace "`r","").TrimEnd("`n")
        if ($actual.TrimEnd("`n") -ne $expected) { $ok = $false }
        $built = ($LASTEXITCODE -eq 0)
    } else {
        & $strata build $dir --force | Out-Null
        $built = ($LASTEXITCODE -eq 0)
        if (-not $built) { $ok = $false }
    }
    if ($ok -and $built) {
        $again = (& $strata build $dir) -join "`n"
        if ($again -notlike "up to date*") { $ok = $false; Write-Host "      (second build wasn't cached: $again)" -ForegroundColor Yellow }
    }
    if ($ok) { Write-Host "PASS  project/$name" -ForegroundColor Green; $script:pass++ }
    else     { Write-Host "FAIL  project/$name" -ForegroundColor Red;   $script:fail++ }
}

# --- incremental split build: editing one function body recompiles one C file ---------
$incDir = Join-Path $here "embed\build\incremental"
if (Test-Path $incDir) { Remove-Item $incDir -Recurse -Force }
Copy-Item (Join-Path $here "projects\multi") $incDir -Recurse
if (Test-Path (Join-Path $incDir "build")) { Remove-Item (Join-Path $incDir "build") -Recurse -Force }
& $strata build $incDir | Out-Null
$textMod = Join-Path $incDir "src\parts\text.strata"
(Get-Content $textMod -Raw).Replace("0..300", "0..301") | Set-Content $textMod -NoNewline
$rebuild = (& $strata build $incDir) -join "`n"
$second  = ((& $strata run $incDir) -join "`n") -replace "`r",""
if ($rebuild -match "\(1 of \d+ C files compiled" -and $second.StartsWith("1`n3010")) {
    Write-Host "PASS  build/incremental (one edited module -> one C file recompiled)" -ForegroundColor Green; $pass++
} else {
    Write-Host "FAIL  build/incremental: $rebuild" -ForegroundColor Red; $fail++
}

# --- backends: native (Strata's own x86-64 code) and C must agree ----------------------------
# The run goldens above went through the default backend: native wherever it can build the
# program (single files build optimized). Run them again forced through each backend, so a
# silent fallback to C can't hide a native regression, and the C backend stays covered.
# (projects/pure covers native debug builds, unoptimized.)
$runDir = Join-Path $here "run"
foreach ($backend in @("native", "c")) {
    $bad = @()
    Get-ChildItem -Path $runDir -Filter *.expected | ForEach-Object {
        $name = [IO.Path]::GetFileNameWithoutExtension($_.Name)
        $src  = Join-Path $examples "$name.strata"
        $usesC = (Get-Content $src -Raw) -match "(?m)^\s*import\s*[<`"]"   # C headers: C backend only
        if (-not ($backend -eq "native" -and $usesC)) {
            $actual   = ((& $strata run $src --backend $backend) -join "`n") -replace "`r",""
            $expected = ((Get-Content $_.FullName -Raw) -replace "`r","").TrimEnd("`n")
            if ($actual.TrimEnd("`n") -ne $expected) { $bad += $name }
        }
    }
    if ($bad.Count -eq 0) { Write-Host "PASS  backend/$backend (every run golden)" -ForegroundColor Green; $pass++ }
    else { Write-Host "FAIL  backend/$backend ($($bad -join ', '))" -ForegroundColor Red; $fail++ }
}
# The CrossPlatform library's window (lib/CrossPlatform*.strata), natively: open it, close
# it the way a user would (WM_CLOSE), and the program must notice and end.
$winSrc = Join-Path $examples "platform_window.strata"
$null = & $strata build $winSrc --backend native --force
$winOk = $false
if ($LASTEXITCODE -eq 0) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $examples "platform_window.exe")
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    for ($t = 0; $t -lt 50 -and $proc.MainWindowHandle -eq [IntPtr]::Zero; $t++) { Start-Sleep -Milliseconds 100; $proc.Refresh() }
    $null = $proc.CloseMainWindow()
    if ($proc.WaitForExit(5000)) { $winOk = ($proc.StandardOutput.ReadToEnd().Trim() -eq "window closed") }
    else { $proc.Kill() }
}
if ($winOk) { Write-Host "PASS  library/CrossPlatform-window (opened natively, closed by the user)" -ForegroundColor Green; $pass++ }
else { Write-Host "FAIL  library/CrossPlatform-window" -ForegroundColor Red; $fail++ }

# The raylib examples (graphical: built, not run) declare raylib in a foreign block
# (examples/raylib.strata), so they build natively - linked by Strata's linker, straight
# against libraylib.dll - and through C, with raylib.h.
$raylibDll = $null
$gccDir = $null
if (Get-Command gcc -ErrorAction SilentlyContinue) { $gccDir = Split-Path (Get-Command gcc).Source }
if ($gccDir -and (Test-Path (Join-Path $gccDir "libraylib.dll")) -and (Test-Path (Join-Path $gccDir "..\include\raylib.h"))) {
    $raylibDll = Join-Path $gccDir "libraylib.dll"
    $bad = @()
    foreach ($name in @("window", "sprite", "balls")) {
        foreach ($backend in @("native", "c")) {
            $out = (& $strata build (Join-Path $examples "$name.strata") --backend $backend --force) -join " "
            if ($LASTEXITCODE -ne 0 -or $out -notmatch "built") { $bad += "$name/$backend" }
            if ($backend -eq "native" -and $out -match "linked by") { $bad += "$name/$backend (linked by the C toolchain)" }
        }
    }
    if ($bad.Count -eq 0) { Write-Host "PASS  backend/raylib (window, sprite, balls: native and C)" -ForegroundColor Green; $pass++ }
    else { Write-Host "FAIL  backend/raylib ($($bad -join ', '))" -ForegroundColor Red; $fail++ }
} else {
    Write-Host "SKIP  backend/raylib (raylib not installed)" -ForegroundColor Yellow
}
# Strata's assembler: for each example (debug and optimized), its object file must
# disassemble to exactly the instructions GNU as makes of the same assembly (jump targets,
# padding and objdump's address comments aside: GNU as picks short jumps).
if (Get-Command objdump -ErrorAction SilentlyContinue) {
    $tmp = Join-Path $here "embed\build"
    if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp | Out-Null }
    $sFile = Join-Path $tmp "asmcheck.s"; $gasObj = Join-Path $tmp "asmcheck_gas.o"; $ourObj = Join-Path $tmp "asmcheck_ours.o"
    function Get-Insns([string]$obj) {
        & objdump -d --no-show-raw-insn $obj | ForEach-Object {
            if ($_ -match '^\s+[0-9a-f]+:\t(.*)$') {
                $i = $Matches[1] -replace '\s*#.*$','' -replace '^(j[a-z]+|call)\s+.*$','$1' -replace '\s+',' '
                $i = $i.Trim()
                if ($i -notmatch 'nop' -and $i -ne 'xchg %ax,%ax') { $i }
            }
        }
    }
    $bad = @(); $count = 0
    foreach ($name in @("abi", "hello", "loops", "matrix", "run1", "strings", "switch", "arrays", "casts", "list")) {
        foreach ($mode in @(@(), @("--release"))) {
            $asmText = (& $strata asm (Join-Path $examples "$name.strata") @mode) -join "`n"
            [IO.File]::WriteAllText($sFile, $asmText + "`n")
            & gcc -c $sFile -o $gasObj 2>&1 | Out-Null
            & $strata assemble $sFile $ourObj | Out-Null
            if ($LASTEXITCODE -ne 0) { $bad += "$name $mode (assembler failed)"; continue }
            $g = @(Get-Insns $gasObj); $o = @(Get-Insns $ourObj)
            $count += $g.Count
            if (($g -join "`n") -ne ($o -join "`n")) { $bad += "$name $mode" }
        }
    }
    if ($bad.Count -eq 0) { Write-Host "PASS  backend/assembler ($count instructions identical to GNU as)" -ForegroundColor Green; $pass++ }
    else { Write-Host "FAIL  backend/assembler ($($bad -join ', '))" -ForegroundColor Red; $fail++ }
} else {
    Write-Host "SKIP  backend/assembler (no objdump)" -ForegroundColor Yellow
}

# Machine code straight from the code generator (a build: no assembly text) must be the
# very bytes the text path makes (`stratac asm` + `stratac assemble`), for every example.
$tmpd = Join-Path $here "embed\build"
if (-not (Test-Path $tmpd)) { New-Item -ItemType Directory -Path $tmpd | Out-Null }
$sTxt = Join-Path $tmpd "direct.s"; $oTxt = Join-Path $tmpd "direct_text.o"
$bad = @(); $count = 0
Get-ChildItem -Path $examples -Filter *.strata | ForEach-Object {
    $srcText = Get-Content $_.FullName -Raw
    # (C headers, C libraries: not native; modules without a main: not programs)
    if ($srcText -match "(?m)^\s*import\s*[<`"]" -or $srcText -match "(?m)^import raylib" -or $srcText -match "(?m)^\s*link\s") { return }
    $b = [IO.Path]::GetFileNameWithoutExtension($_.Name)
    $savedPref = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    $null = & $strata build $_.FullName --backend native --force 2>&1
    $ErrorActionPreference = $savedPref
    $oDirect = Join-Path $examples "$b.o"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $oDirect)) { return }
    $asmText = (& $strata asm $_.FullName --release) -join "`n"
    [IO.File]::WriteAllText($sTxt, $asmText + "`n")
    $null = & $strata assemble $sTxt $oTxt
    $count++
    if ((Get-FileHash $oDirect).Hash -ne (Get-FileHash $oTxt).Hash) { $bad += $b }
}
if ($bad.Count -eq 0 -and $count -gt 0) { Write-Host "PASS  backend/direct-encoding ($count examples: the same bytes as through assembly text)" -ForegroundColor Green; $pass++ }
else { Write-Host "FAIL  backend/direct-encoding ($($bad -join ', '))" -ForegroundColor Red; $fail++ }

# Cross-compiling: a Linux x86-64 program built here (runs on CI's Linux: tests/run.sh)
$xOut = (& $strata build (Join-Path $examples "hello.strata") --target linux-x64 --force) -join " "
$xExe = Join-Path $examples "hello"
$xOk = $false
if ($LASTEXITCODE -eq 0 -and (Test-Path $xExe)) {
    $h = [IO.File]::ReadAllBytes($xExe)
    $xOk = $h.Length -gt 64 -and $h[0] -eq 127 -and $h[1] -eq 69 -and $h[2] -eq 76 -and $h[3] -eq 70 -and $h[16] -eq 2 -and $h[18] -eq 62
}
if ($xOk) { Write-Host "PASS  backend/cross-linux (hello built for linux-x64: an x86-64 ELF executable)" -ForegroundColor Green; $pass++ }
else { Write-Host "FAIL  backend/cross-linux: $xOut" -ForegroundColor Red; $fail++ }

# Cross-compiling for macOS ARM64: hello as a signed Mach-O executable (runs on CI's Mac)
$mOut = (& $strata build (Join-Path $examples "hello.strata") --target macos-arm64 --force) -join " "
$mOk = $false
if ($LASTEXITCODE -eq 0 -and (Test-Path $xExe)) {
    $h = [IO.File]::ReadAllBytes($xExe)
    # MH_MAGIC_64, CPU_TYPE_ARM64, MH_EXECUTE, and an LC_CODE_SIGNATURE among the load commands
    $mOk = $h.Length -gt 64 -and [BitConverter]::ToUInt32($h, 0) -eq 4277009103 -and [BitConverter]::ToUInt32($h, 4) -eq 0x0100000C -and [BitConverter]::ToUInt32($h, 12) -eq 2
    $signed = $false
    $at = 32
    for ($c = 0; $mOk -and $c -lt [BitConverter]::ToUInt32($h, 16); $c++) {
        if ([BitConverter]::ToUInt32($h, $at) -eq 0x1D) { $signed = $true }
        $at += [BitConverter]::ToUInt32($h, $at + 4)
    }
    $mOk = $mOk -and $signed
    Remove-Item $xExe -ErrorAction SilentlyContinue
}
if ($mOk) { Write-Host "PASS  backend/cross-macos (hello built for macos-arm64: a signed ARM64 Mach-O executable)" -ForegroundColor Green; $pass++ }
else { Write-Host "FAIL  backend/cross-macos: $mOut" -ForegroundColor Red; $fail++ }

# The ARM64 assembler: every example's ARM64 assembly, assembled by Strata and by clang,
# must give the same __text bytes (when an LLVM clang that targets ARM64 is installed)
$clang = $null
if (Get-Command clang -ErrorAction SilentlyContinue) { $clang = (Get-Command clang).Source }
elseif (Test-Path "C:\Program Files\LLVM\bin\clang.exe") { $clang = "C:\Program Files\LLVM\bin\clang.exe" }
function Get-MachText([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    $at = 32
    for ($c = 0; $c -lt [BitConverter]::ToUInt32($b, 16); $c++) {
        if ([BitConverter]::ToUInt32($b, $at) -eq 0x19) {
            for ($k = 0; $k -lt [BitConverter]::ToUInt32($b, $at + 64); $k++) {
                $s = $at + 72 + 80 * $k
                if ([Text.Encoding]::ASCII.GetString($b, $s, 6) -eq "__text") {
                    $size = [BitConverter]::ToUInt64($b, $s + 40); $off = [BitConverter]::ToUInt32($b, $s + 48)
                    return [BitConverter]::ToString($b, $off, $size)
                }
            }
        }
        $at += [BitConverter]::ToUInt32($b, $at + 4)
    }
    return ""
}
if ($clang) {
    $tmp = Join-Path $compiler "build"
    $count = 0
    $bad = @()
    $savedPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    foreach ($ex in (Get-ChildItem (Join-Path $examples "*.strata"))) {
        foreach ($mode in @("", "--release")) {
            $asmArgs = @("asm", $ex.FullName, "--target", "macos-arm64")
            if ($mode) { $asmArgs += $mode }
            $text = (& $strata @asmArgs 2>$null) -join "`n"
            if ($LASTEXITCODE -ne 0) { continue }
            $sOurs = Join-Path $tmp "a64check.s"; $sClang = Join-Path $tmp "a64check_clang.s"
            $oOurs = Join-Path $tmp "a64check_ours.o"; $oClang = Join-Path $tmp "a64check_clang.o"
            [IO.File]::WriteAllText($sOurs, $text + "`n")
            [IO.File]::WriteAllText($sClang, ($text -replace '\.section \.rdata,"dr"', '.section __TEXT,__const') + "`n")
            $null = & $strata assemble $sOurs $oOurs --target macos-arm64 2>&1
            $null = & $clang -target arm64-apple-macos11 -c $sClang -o $oClang 2>&1
            $count++
            if ((Get-MachText $oOurs) -ne (Get-MachText $oClang)) { $bad += "$($ex.BaseName)$mode" }
        }
    }
    $ErrorActionPreference = $savedPref
    if ($bad.Count -eq 0 -and $count -gt 0) { Write-Host "PASS  backend/arm64-assembler ($count programs: the same code as clang's assembler)" -ForegroundColor Green; $pass++ }
    else { Write-Host "FAIL  backend/arm64-assembler ($($bad -join ', '))" -ForegroundColor Red; $fail++ }
} else {
    Write-Host "SKIP  backend/arm64-assembler (no LLVM clang)" -ForegroundColor Yellow
}

# No C compiler at all: with gcc off PATH, native programs still build and run (Strata
# compiles, assembles and links them; the runtime is the prebuilt lib/srt.o).
$savedPath = $env:Path
$env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
# raylib's DLL alone on PATH (no gcc beside it): a raylib example links against it
$dllDir = Join-Path $here "embed\build\dllonly"
if ($raylibDll -and (Test-Path $raylibDll)) {
    if (-not (Test-Path $dllDir)) { New-Item -ItemType Directory -Path $dllDir | Out-Null }
    Copy-Item $raylibDll $dllDir -Force
    $env:Path = "$env:Path;$dllDir"
}
$noCc = @()
try {
    if ($raylibDll) {
        $out = (& $strata build (Join-Path $examples "window.strata") --backend native --force) -join " "
        if ($LASTEXITCODE -ne 0 -or $out -match "linked by") { $noCc += "window (raylib)" }
    }
    # the compiler builds itself, and the compiler it builds works
    # (the copy runs from compiler\build\, where it finds compiler\lib\)
    $selfExe  = Join-Path $compiler "src\stratac.exe"
    $selfCopy = Join-Path $compiler "build\selftest.exe"
    & $strata build (Join-Path $compiler "src\stratac.strata") --backend native --force | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $selfExe)) { $noCc += "the compiler itself" }
    else {
        Copy-Item $selfExe $selfCopy -Force
        $out  = ((& $selfCopy run (Join-Path $examples "hello.strata") --force) -join "`n") -replace "`r",""
        $want = ((Get-Content (Join-Path $here "run\hello.expected") -Raw) -replace "`r","").TrimEnd("`n")
        if ($out.TrimEnd("`n") -ne $want) { $noCc += "the compiler itself (its hello)" }
    }
    foreach ($name in @("hello", "abi", "loops", "matrix", "foreign")) {
        $out  = ((& $strata run (Join-Path $examples "$name.strata") --backend native) -join "`n") -replace "`r",""
        $want = ((Get-Content (Join-Path $here "run\$name.expected") -Raw) -replace "`r","").TrimEnd("`n")
        if ($out.TrimEnd("`n") -ne $want) { $noCc += $name }
    }
    $pureDir = Join-Path $here "projects\pure"
    $out  = ((& $strata run $pureDir --force --backend native) -join "`n") -replace "`r",""
    $want = ((Get-Content (Join-Path $pureDir "expected.txt") -Raw) -replace "`r","").TrimEnd("`n")
    if ($out.TrimEnd("`n") -ne $want) { $noCc += "projects/pure" }
} finally { $env:Path = $savedPath }
if ($noCc.Count -eq 0) { Write-Host "PASS  backend/no-c-compiler (native builds with no gcc on PATH)" -ForegroundColor Green; $pass++ }
else { Write-Host "FAIL  backend/no-c-compiler ($($noCc -join ', '))" -ForegroundColor Red; $fail++ }

# the native backend's own assembly (a smoke test of `stratac asm`)
$asm = (& $strata asm (Join-Path $examples "run1.strata")) -join "`n"
if ($LASTEXITCODE -eq 0 -and $asm -match "call fib" -and $asm -match "(?m)^fib:") {
    Write-Host "PASS  backend/asm (stratac asm)" -ForegroundColor Green; $pass++
} else {
    Write-Host "FAIL  backend/asm (stratac asm)" -ForegroundColor Red; $fail++
}

# --- performance: guard against the compiler going quadratic again -------------------
# A generated 20k-line single file must type-check in under 3 s. (It takes ~0.05 s; before
# the fixes in 1.4.0 it took 16 s, because every token re-measured the whole source.)
$perfDir = Join-Path $here "embed\build"
if (-not (Test-Path $perfDir)) { New-Item -ItemType Directory -Path $perfDir | Out-Null }
$perfFile = Join-Path $perfDir "perf20k.strata"
$sb = New-Object System.Text.StringBuilder
for ($f = 0; $f -lt 2500; $f++) {
    [void]$sb.AppendLine("struct T$f { int a; float b; vec3 p }")
    [void]$sb.AppendLine("int f$f(int x) { var t = T$f{ x, 1.5, vec3(1, 2, 3) }")
    [void]$sb.AppendLine("    int acc = t.a + $f")
    [void]$sb.AppendLine("    for i in 0..3 { acc += i * 2 }")
    [void]$sb.AppendLine("    if acc > 100 { return acc - 1 }")
    [void]$sb.AppendLine("    return acc }")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("")
}
[void]$sb.AppendLine("print(f0(1))")
[IO.File]::WriteAllText($perfFile, $sb.ToString())
$t = Measure-Command { & $strata check $perfFile | Out-Null }
if ($LASTEXITCODE -eq 0 -and $t.TotalSeconds -lt 3) {
    Write-Host ("PASS  perf/check-20k-lines ({0:N2} s)" -f $t.TotalSeconds) -ForegroundColor Green; $pass++
} else {
    Write-Host ("FAIL  perf/check-20k-lines ({0:N2} s, exit {1})" -f $t.TotalSeconds, $LASTEXITCODE) -ForegroundColor Red; $fail++
}

# --- limits: deep nesting is a clean error (not a crash); long chains stay linear ------
$deep = Join-Path $perfDir "deep1001.strata"
[IO.File]::WriteAllText($deep, "var x = " + ("(" * 1001) + "1" + (")" * 1001) + "`nprint(x)`n")
$deepOut = (& $strata check $deep) -join "`n"
if ($LASTEXITCODE -eq 1 -and $deepOut -match "nested too deeply \(more than 1000 levels\)") {
    Write-Host "PASS  limits/nesting-1001-is-an-error" -ForegroundColor Green; $pass++
} else {
    Write-Host "FAIL  limits/nesting-1001-is-an-error (exit $LASTEXITCODE): $deepOut" -ForegroundColor Red; $fail++
}
$chain = Join-Path $perfDir "chain100k.strata"
[IO.File]::WriteAllText($chain, "var x = " + ((@("1") * 100000) -join " + ") + "`nprint(x)`n")
$t = Measure-Command { & $strata emit $chain | Out-Null }
if ($LASTEXITCODE -eq 0 -and $t.TotalSeconds -lt 3) {
    Write-Host ("PASS  limits/100k-term-expression ({0:N2} s)" -f $t.TotalSeconds) -ForegroundColor Green; $pass++
} else {
    Write-Host ("FAIL  limits/100k-term-expression ({0:N2} s, exit {1})" -f $t.TotalSeconds, $LASTEXITCODE) -ForegroundColor Red; $fail++
}

# --- embedding: host programs using libstrata and a Strata-built dll ---------------
# tests/embed/ holds small "engines": C (the C API), C++ (strata.hpp), C# (Strata.cs, if a
# .NET SDK is installed), and a C program calling tests/projects/lib's dll through its
# generated header. Each one's output must match its expected_*.txt.
$embed   = Join-Path $here "embed"
$binDir  = Join-Path $compiler "bin"
$apiDir  = Join-Path $compiler "api"
$libProj = Join-Path $here "projects\lib\build"
$eb      = Join-Path $embed "build"
if (-not (Test-Path $eb)) { New-Item -ItemType Directory -Path $eb | Out-Null }
$savedPath = $env:Path
$env:Path = "$binDir;$libProj;$env:Path"      # so the hosts find libstrata.dll / mathlib.dll
Push-Location $embed
function Test-Host([string]$name, [scriptblock]$compile, [string]$exe, [string]$expected) {
    & $compile 2>&1 | Out-Null
    $ok = $?
    if ($ok) {
        $out  = ((& $exe) -join "`n") -replace "`r",""
        $want = ((Get-Content (Join-Path $embed $expected) -Raw) -replace "`r","").TrimEnd("`n")
        $ok = ($out.TrimEnd("`n") -eq $want)
    }
    if ($ok) { Write-Host "PASS  embed/$name" -ForegroundColor Green; $script:pass++ }
    else     { Write-Host "FAIL  embed/$name" -ForegroundColor Red;   $script:fail++ }
}
try {
    Test-Host "c-api" { gcc -std=c99 -Wall host_api.c -I $apiDir -L $binDir -lstrata -lpsapi -o build/host_api.exe } "build/host_api.exe" "expected_api.txt"
    Test-Host "strata-dll" { gcc -std=c99 -Wall host_dll.c -I $libProj -L $libProj -lmathlib -o build/host_dll.exe } "build/host_dll.exe" "expected_dll.txt"
    # the same dll, loaded where it didn't ask to be: its base relocations must be right
    Test-Host "dll-relocated" { gcc -std=c99 -Wall host_reloc.c -o build/host_reloc.exe } "build/host_reloc.exe" "expected_reloc.txt"
    Test-Host "cpp" { g++ -std=c++17 -Wall host_cpp.cpp -I $apiDir -L $binDir -lstrata -o build/host_cpp.exe } "build/host_cpp.exe" "expected_cpp.txt"
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        Test-Host "csharp" { dotnet build csharp -c Release -o build/cs --nologo -v q } "build/cs/Embed.exe" "expected_cs.txt"
    } else {
        Write-Host "SKIP  embed/csharp (no .NET SDK)" -ForegroundColor Yellow
    }
} finally {
    Pop-Location
    $env:Path = $savedPath
}

Write-Host ""
Write-Host "$pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
