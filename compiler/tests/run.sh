#!/bin/sh
# tests/run.sh - bootstrap the Strata compiler (build.sh) and validate it, on macOS (ARM64) /
# Linux (x86-64). The same checks as run.ps1 (Windows):
#   1. the bootstrap: stage0 (the pinned release) -> stage1 -> stage2 -> stage3, fixpoint-checked
#   2. goldens: each stage's output vs its golden file, byte-for-byte (ARCHITECTURE.md sec 6)
#   3. CrossPlatform's window, 4. projects, 5. performance & limits, 6. embedding hosts
# Run from anywhere:
#     sh compiler/tests/run.sh
#     sh compiler/tests/run.sh --bootstrap <stratac>    (passed on to build.sh)
#
# A golden file  tests/<stage>/<name>.expected  is compared against the output of
#     stratac <stage> examples/<name>.strata
# using the SHIPPED compiler (bin/stratac, the self-hosted stage3). What differs by OS has
# its own golden: <name>.expected.linux / .expected.macos.
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
    Darwin) dll=dylib; os=macos ;;
    *)      dll=so; os=linux ;;
esac

# --- bootstrap (stage0 -> stage1 -> stage2 -> stage3, with the fixpoint check) ---------
if ! sh "$compiler/build.sh" "$@" >/dev/null; then
    echo "${red}FAIL${off}: bootstrap build failed (run compiler/build.sh to see why)"
    exit 1
fi
ok "bootstrap (pinned release -> stage1 -> stage2 -> stage3, native, fixpoint)"

# --- run each golden ---------------------------------------------------------
for dir in "$here"/*/; do
    stage=$(basename "$dir")
    for exp in "$dir"*.expected; do
        [ -f "$exp" ] || continue
        name=$(basename "$exp" .expected)
        source=$examples/$name.strata
        if [ ! -f "$source" ]; then skip "$stage/$name  (no examples/$name.strata)"; continue; fi
        want=$exp
        [ -f "$exp.$os" ] && want=$exp.$os
        actual=$("$strata" "$stage" "$source" | norm)   # stdout only, like run.ps1
        if [ "$actual" = "$(norm < "$want")" ]; then ok "$stage/$name"
        else
            bad "$stage/$name"
            printf '%s\n' "$actual" > "$compiler/build/golden-actual.txt"
            norm < "$want" | diff - "$compiler/build/golden-actual.txt" | head -12 | sed "s/^/    $name: /"
        fi
    done
done

# --- the CrossPlatform library's window (lib/CrossPlatform/linux.strata: X11), natively ---
# On a virtual X server: open it, close it from outside (xdotool), and the program must
# notice and end.
if [ "$os" = linux ] && command -v Xvfb >/dev/null 2>&1 && command -v xdotool >/dev/null 2>&1; then
    winok=0
    winout=$(mktemp)
    if "$strata" build "$examples/platform_window.strata" --force >/dev/null 2>&1; then
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

# --- the CrossPlatform library's window on macOS (lib/CrossPlatform/macos.strata: Cocoa) ---
# Natively: open it, let it run a few frames, close it; the program must notice and end.
# (A machine with no window server can't open one: then it's skipped.)
if [ "$os" = macos ]; then
    wdir=$(mktemp -d)
    cat > "$wdir/win.strata" <<'EOF'
import CrossPlatform
if !create_window(320, 200, "Strata - CrossPlatform test") {
    print("couldn't open a window")
} else {
    var frames = 0
    set_window_title("Strata - frames")
    set_window_size(400, 300)
    while poll_events() {
        frames += 1
        if frames == 30 { print(window_width() > 0); close_window() }
    }
    print("window closed")
}
EOF
    wout=$("$strata" run "$wdir/win.strata" --force 2>&1 | norm)
    case "$wout" in
        "couldn't open a window") skip "library/CrossPlatform-window (no window server here)" ;;
        "$(printf '1\nwindow closed')") ok "library/CrossPlatform-window (Cocoa, natively: opened, run, closed)" ;;
        *) printf '%s\n' "$wout" | head -8 | sed "s/^/    window: /"; bad "library/CrossPlatform-window" ;;
    esac
    rm -rf "$wdir"
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

eb=$here/embed/build
mkdir -p "$eb"

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
t0=$(now); "$strata" build "$chain" --force >/dev/null 2>&1; rc=$?; t1=$(now)
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
    if built=$("$@" 2>&1); then
        out=$("./build/$name" 2>&1 | norm)
        if [ "$out" = "$(norm < "$want")" ]; then ok "embed/$name"; return; fi
        printf '%s\n' "$out" | head -8 | sed "s/^/    $name: /"
    else
        printf '%s\n' "$built" | head -8 | sed "s/^/    $name (build): /"
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
