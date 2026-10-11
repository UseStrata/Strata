#!/bin/sh
# build.sh - bootstrap the Strata compiler on Linux (x86-64) / macOS (ARM64) and build
# compiler/bin/ :
#     stratac                   front-end #1 (the compiler CLI)
#     console                   front-end #2 (the explorer console)
#     libstrata.so / .dylib     the compiler as a shared library
# (On Windows use build.ps1; it does the same.)
#
# The compiler is written in Strata, so building it needs a Strata compiler:
#
#   stage0  a PINNED released stratac for this OS (bootstrap.txt), downloaded once and cached
#           (or any stratac that runs here:  sh compiler/build.sh --bootstrap <stratac>)
#   stage1  stage0 builds src/stratac.strata  (linked with stage0's own runtime)
#   stage2  stage1 builds src/stratac.strata  (after compiling today's lib/srt.strata)
#   stage3  stage2 builds it again
#
# Every stage is built natively: Strata's own backend, assembler and linker - no C
# compiler. Fixpoint check: stage2 and stage3 must be byte-identical programs (and stage1
# and stage2 must compile the runtime the same); stage3 ships. The stage0 rule: src/ may
# only use language features the pinned release supports.
#
#     sh compiler/build.sh
#     sh compiler/build.sh --bootstrap <stratac>

set -eu

here=$(cd "$(dirname "$0")" && pwd)    # .../compiler
src=$here/src
lib=$here/lib
bin=$here/bin
boot=$here/build                       # stage compilers (a sibling of lib/, so they find it)

stage0=""
while [ $# -gt 0 ]; do
    case $1 in
        --bootstrap)  [ $# -ge 2 ] || { echo "error: --bootstrap needs a path" >&2; exit 2; }
                      stage0=$2; shift 2 ;;
        *) echo "usage: sh build.sh [--bootstrap <stratac>]" >&2; exit 2 ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }
say()  { echo "$*"; }

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  target=linux-x64 ;;
    Darwin-arm64)  target=macos-arm64 ;;
    *) fail "Strata builds natively for Linux x86-64, macOS ARM64 and Windows x86-64 (this is $(uname -s) $(uname -m))" ;;
esac
rt=$lib/srt-$target.o                  # the runtime native programs link

mkdir -p "$bin" "$boot"

# --- stage0: the pinned release (or the compiler given) ------------------------
if [ -z "$stage0" ]; then
    pin=$(tr -d ' \r\n' < "$here/bootstrap.txt")
    cache=$boot/bootstrap-$pin-$target
    stage0=$cache/strata/stratac
    if [ ! -x "$stage0" ]; then
        url=https://github.com/UseStrata/Strata/releases/download/v$pin/strata-$pin-$target.tar.gz
        say "downloading bootstrap compiler v$pin ($target) ..."
        rm -rf "$cache"
        mkdir -p "$cache"
        if command -v curl >/dev/null 2>&1; then fetch="curl -fsSL $url"; else fetch="wget -qO- $url"; fi
        if ! $fetch | tar -xzf - -C "$cache"; then
            # offline: an installed stratac (the fixpoint check still guards the result)
            installed=$(command -v stratac || true)
            [ -n "$installed" ] || fail "cannot download $url and no stratac on PATH; pass --bootstrap <stratac>"
            say "download failed; using installed $installed as stage0"
            stage0=$installed
        fi
    fi
fi
[ -x "$stage0" ] || fail "bootstrap compiler not found: $stage0"
say "stage0: $("$stage0" version)"

# Build src/stratac.strata with compiler $2; copy the result to $3. (Each stage runs from
# its own copy, so it never overwrites the program that is running.)
build_stage() {
    say "building $1 ..."
    "$2" build "$src/stratac.strata" --force >/dev/null || fail "$1 build failed"
    cp "$src/stratac" "$3"
}
# Compile lib/srt.strata with compiler $1 into the runtime object.
build_runtime() {
    "$1" object "$lib/srt.strata" "$rt" || fail "lib/srt-$target.o build failed ($1)"
}

# --- stage1 (with stage0's runtime), stage2, stage3 (each after today's runtime) ---
stage1=$boot/stage1
stage2=$boot/stage2
stage3=$boot/stage3
build_stage "stage1 (built by stage0)" "$stage0" "$stage1"
build_runtime "$stage1"
build_stage "stage2 (built by stage1)" "$stage1" "$stage2"
cp "$rt" "$boot/srt-stage1.o"
build_runtime "$stage2"
build_stage "stage3 (built by stage2)" "$stage2" "$stage3"

# --- fixpoint: stage2 and stage3 must be the same program, byte for byte -------------
cmp -s "$boot/srt-stage1.o" "$rt" || fail "fixpoint check FAILED: stage1 and stage2 compile lib/srt.strata differently"
cmp -s "$stage2" "$stage3" || fail "fixpoint check FAILED: stage2 and stage3 differ"
say "fixpoint ok: stage2 and stage3 are identical"

cp "$stage3" "$bin/stratac"
stratac=$bin/stratac

# --- console and libstrata: built by the shipped compiler ----------------------
say "building console ..."
"$stratac" build "$src/console.strata" --force >/dev/null || fail "console build failed"
cp "$src/console" "$bin/console"
say "building libstrata ..."
"$stratac" build "$here/api" --force >/dev/null || fail "libstrata build failed"

say ""
say "artifacts in compiler/bin/ :"
for f in "$bin"/stratac "$bin"/console "$bin"/libstrata.*; do
    [ -f "$f" ] && printf '  %-18s %10s bytes\n' "$(basename "$f")" "$(wc -c < "$f" | tr -d ' ')"
done
exit 0
