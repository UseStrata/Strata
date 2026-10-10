#!/bin/sh
# tests/run.sh - bootstrap the Strata compiler (build.sh) and validate it, on macOS / Linux.
# The same checks as run.ps1 (Windows):
#   1. the bootstrap: stage0 (the C seed) -> stage1 -> stage2, fixpoint-checked
#   2. goldens: each stage's output vs its golden file, byte-for-byte (ARCHITECTURE.md sec 6)
#   3. projects, 4. incremental builds, 5. performance & limits, 6. embedding hosts
# Run from anywhere:
#     sh compiler/tests/run.sh
#     sh compiler/tests/run.sh --bootstrap <stratac>    (passed on to build.sh)
#
# A golden file  tests/<stage>/<name>.expected  is compared against the output of
#     stratac <stage> examples/<name>.strata
# using the SHIPPED compiler (bin/stratac, the self-hosted stage2).
# Exit code 0 = all passed, 1 = a mismatch or build failure.

set -u

here=$(cd "$(dirname "$0")" && pwd)    # .../compiler/tests
compiler=$(dirname "$here")
examples=$compiler/examples
strata=$compiler/bin/stratac
pass=0
fail=0

if [ -t 1 ]; then green=$(printf '\033[32m'); red=$(printf '\033[31m'); yellow=$(printf '\033[33m'); off=$(printf '\033[0m')
else green=; red=; yellow=; off=; fi
ok()   { echo "${green}PASS${off}  $*"; pass=$((pass + 1)); }
bad()  { echo "${red}FAIL${off}  $*"; fail=$((fail + 1)); }
skip() { echo "${yellow}SKIP${off}  $*"; }

# Output with CRs removed and trailing newlines dropped (like run.ps1's normalization)
norm() { tr -d '\r' | awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] == "") n--; for (i = 1; i <= n; i++) print lines[i] }'; }

# seconds since the epoch, with fractions
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time' 2>/dev/null || date +%s; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }
under() { awk -v t="$1" -v max="$2" 'BEGIN { exit !(t < max) }'; }

case $(uname -s) in
    Darwin) dll=dylib ;;
    *)      dll=so ;;
esac

# --- bootstrap (stage0 -> stage1 -> stage2, with the fixpoint check) ---------
if ! sh "$compiler/build.sh" "$@" >/dev/null; then
    echo "${red}FAIL${off}: bootstrap build failed (run compiler/build.sh to see why)"
    exit 1
fi
ok "bootstrap (C seed -> stage1 -> stage2, fixpoint)"

# --- run each golden ---------------------------------------------------------
for dir in "$here"/*/; do
    stage=$(basename "$dir")
    for exp in "$dir"*.expected; do
        [ -f "$exp" ] || continue
        name=$(basename "$exp" .expected)
        source=$examples/$name.strata
        if [ ! -f "$source" ]; then skip "$stage/$name  (no examples/$name.strata)"; continue; fi
        if grep -q "^import CrossPlatform" "$source"; then skip "$stage/$name  (CrossPlatform: in the native pass, on Linux x86-64)"; continue; fi
        actual=$("$strata" "$stage" "$source" | norm)   # stdout only, like run.ps1
        expected=$(norm < "$exp")
        if [ "$actual" = "$expected" ]; then ok "$stage/$name"; else bad "$stage/$name"; fi
    done
done

# --- the native backend, where it builds programs (Linux x86-64) --------------------
# Every run golden again, forced through Strata's own backend, assembler and ELF linker
# (no C compiler; the runtime is lib/srt-linux-x64.o).
if [ -f "$compiler/lib/srt-linux-x64.o" ]; then
    badn=""
    for exp in "$here"/run/*.expected; do
        name=$(basename "$exp" .expected)
        source=$examples/$name.strata
        # (C headers: not natively; what differs by OS: its .expected.linux)
        if grep -q '^import [<"]' "$source"; then continue; fi
        want=$exp
        [ -f "$exp.linux" ] && want=$exp.linux
        actual=$("$strata" run "$source" --backend native --force 2>&1 | norm)
        [ "$actual" = "$(norm < "$want")" ] || badn="$badn $name"
    done
    if [ -z "$badn" ]; then ok "backend/native (every run golden, Linux x86-64)"; else bad "backend/native:$badn"; fi
fi

# --- the CrossPlatform library's window (lib/CrossPlatform/linux.strata: X11), natively ---
# On a virtual X server: open it, close it from outside (xdotool), and the program must
# notice and end.
if [ -f "$compiler/lib/srt-linux-x64.o" ] && command -v Xvfb >/dev/null 2>&1 && command -v xdotool >/dev/null 2>&1; then
    winok=0
    winout=$(mktemp)
    if "$strata" build "$examples/platform_window.strata" --backend native --force >/dev/null 2>&1; then
        Xvfb :87 >/dev/null 2>&1 &
        xvfb=$!
        sleep 1
        DISPLAY=:87 timeout 15 "$examples/platform_window" > "$winout" 2>&1 &
        prog=$!
        win=""
        for t in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            win=$(DISPLAY=:87 xdotool search --name "Strata" 2>/dev/null | head -1)
            [ -n "$win" ] && break
            sleep 0.25
        done
        [ -n "$win" ] && DISPLAY=:87 xdotool windowclose "$win" >/dev/null 2>&1
        wait $prog
        [ "$(norm < "$winout")" = "window closed" ] && winok=1
        kill $xvfb 2>/dev/null
        rm -f "$examples/platform_window" "$winout"
    fi
    if [ $winok -eq 1 ]; then ok "library/CrossPlatform-window (X11, natively: opened, closed from outside)"; else bad "library/CrossPlatform-window"; fi
fi

# --- projects (strata.toml): the build system ---------------------------------
# tests/projects/<name>/ is a project. If it has expected.txt, `stratac run <dir> --force`
# must print exactly that (a failing project's expected.txt holds its errors); otherwise
# `stratac build <dir> --force` must succeed (e.g. a dll). Then, for projects that built,
# a second `stratac build` must hit the cache ("up to date").
for dir in "$here"/projects/*/; do
    dir=${dir%/}
    name=$(basename "$dir")
    good=1
    if [ -f "$dir/expected.txt" ]; then
        actual=$("$strata" run "$dir" --force); rc=$?
        actual=$(printf '%s\n' "$actual" | norm)
        [ "$actual" = "$(norm < "$dir/expected.txt")" ] || good=0
    else
        "$strata" build "$dir" --force >/dev/null 2>&1; rc=$?
        [ $rc -eq 0 ] || good=0
    fi
    if [ $good -eq 1 ] && [ $rc -eq 0 ]; then
        again=$("$strata" build "$dir")
        case $again in
            "up to date"*) ;;
            *) good=0; echo "      (second build wasn't cached: $again)" ;;
        esac
    fi
    if [ $good -eq 1 ]; then ok "project/$name"; else bad "project/$name"; fi
done

# --- incremental split build: editing one function body recompiles one C file ---------
eb=$here/embed/build
mkdir -p "$eb"
inc=$eb/incremental
rm -rf "$inc"
cp -R "$here/projects/multi" "$inc"
rm -rf "$inc/build"
"$strata" build "$inc" >/dev/null 2>&1
text=$inc/src/parts/text.strata
sed 's/0\.\.300/0..301/' "$text" > "$text.new" && mv "$text.new" "$text"
rebuild=$("$strata" build "$inc" 2>&1)
second=$("$strata" run "$inc" | norm)
first_two=$(printf '%s\n' "$second" | head -2 | tr '\n' ' ')
if printf '%s' "$rebuild" | grep -Eq '\(1 of [0-9]+ C files compiled' && [ "$first_two" = "1 3010 " ]; then
    ok "build/incremental (one edited module -> one C file recompiled)"
else
    bad "build/incremental: $rebuild"
fi

# --- performance: guard against the compiler going quadratic again -------------------
# A generated 20k-line single file must type-check in under 3 s.
perf=$eb/perf20k.strata
awk 'BEGIN {
    for (f = 0; f < 2500; f++) {
        printf "struct T%d { int a; float b; vec3 p }\n", f
        printf "int f%d(int x) { var t = T%d{ x, 1.5, vec3(1, 2, 3) }\n", f, f
        printf "    int acc = t.a + %d\n", f
        print  "    for i in 0..3 { acc += i * 2 }"
        print  "    if acc > 100 { return acc - 1 }"
        print  "    return acc }"
        print  ""
        print  ""
    }
    print "print(f0(1))"
}' > "$perf"
t0=$(now); "$strata" check "$perf" >/dev/null 2>&1; rc=$?; t1=$(now)
t=$(elapsed "$t0" "$t1")
if [ $rc -eq 0 ] && under "$t" 3; then ok "perf/check-20k-lines (${t} s)"; else bad "perf/check-20k-lines (${t} s, exit $rc)"; fi

# --- limits: deep nesting is a clean error (not a crash); long chains stay linear ------
deep=$eb/deep1001.strata
awk 'BEGIN { s = "var x = "; for (i = 0; i < 1001; i++) s = s "("; s = s "1"; for (i = 0; i < 1001; i++) s = s ")"; print s; print "print(x)" }' > "$deep"
deep_out=$("$strata" check "$deep" 2>&1); rc=$?
if [ $rc -eq 1 ] && printf '%s' "$deep_out" | grep -q "nested too deeply (more than 1000 levels)"; then
    ok "limits/nesting-1001-is-an-error"
else
    bad "limits/nesting-1001-is-an-error (exit $rc): $deep_out"
fi
chain=$eb/chain100k.strata
awk 'BEGIN { printf "var x = 1"; for (i = 1; i < 100000; i++) printf " + 1"; print ""; print "print(x)" }' > "$chain"
t0=$(now); "$strata" emit "$chain" >/dev/null 2>&1; rc=$?; t1=$(now)
t=$(elapsed "$t0" "$t1")
if [ $rc -eq 0 ] && under "$t" 3; then ok "limits/100k-term-expression (${t} s)"; else bad "limits/100k-term-expression (${t} s, exit $rc)"; fi

# --- embedding: host programs using libstrata and a Strata-built shared library ---------
# tests/embed/ holds small "engines": C (the C API), C++ (strata.hpp), C# (Strata.cs, if a
# .NET SDK is installed), and a C program calling tests/projects/lib's library through its
# generated header. Each one's output must match its expected_*.txt. The hosts find the
# libraries through an rpath (macOS install names are @rpath/<name>, Linux sonames <name>).
embed=$here/embed
bin=$compiler/bin
api=$compiler/api
libproj=$here/projects/lib/build
cc=${STRATA_CC:-cc}
cxx=${CXX:-c++}
cd "$embed" || exit 1
test_host() {   # name, expected file, compile command...
    name=$1; want=$2; shift 2
    if "$@" >/dev/null 2>&1; then
        out=$("./build/$name" | norm)
        if [ "$out" = "$(norm < "$want")" ]; then ok "embed/$name"; return; fi
    fi
    bad "embed/$name"
}
test_host c-api expected_api.txt "$cc" -std=c99 -Wall host_api.c -I"$api" -L"$bin" -lstrata -Wl,-rpath,"$bin" -o build/c-api
test_host strata-dll expected_dll.txt "$cc" -std=c99 -Wall host_dll.c -I"$libproj" "$libproj/mathlib.$dll" -Wl,-rpath,"$libproj" -o build/strata-dll
test_host cpp expected_cpp.txt "$cxx" -std=c++17 -Wall host_cpp.cpp -I"$api" -L"$bin" -lstrata -Wl,-rpath,"$bin" -o build/cpp
if command -v dotnet >/dev/null 2>&1; then
    skip "embed/csharp (Strata.cs loads libstrata.dll by name; not set up for this platform yet)"
else
    skip "embed/csharp (no .NET SDK)"
fi

echo ""
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
