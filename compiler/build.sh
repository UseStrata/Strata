#!/bin/sh
# build.sh - bootstrap the Strata compiler on macOS / Linux and build compiler/bin/ :
#     stratac                   front-end #1 (the compiler CLI)
#     console                   front-end #2 (the explorer console)
#     libstrata.dylib / .so     the compiler as a shared library (+ bin/libstrata.h)
# (On Windows use build.ps1; it does the same, from a pinned release.)
#
# The compiler is written in Strata, so building it needs a Strata compiler:
#
#   stage0  the C SEED: seed/stratac.c, a stratac already compiled to portable C (with the
#           headers it was generated against), built with cc. See seed/README.md.
#           Or any stratac that runs here:  sh compiler/build.sh --bootstrap <stratac>
#   stage1  stage0 builds src/stratac.strata
#   stage2  stage1 builds src/stratac.strata  (the compiler, built by itself)
#
# Fixpoint check: stage1 and stage2 must emit byte-identical C for the compiler. stage2 is
# what ships. The seed rule matches build.ps1's: src/ may only use language features the
# seed's compiler supports.
#
#     sh compiler/build.sh                    bootstrap from the seed, build bin/
#     sh compiler/build.sh --bootstrap <exe>  use that stratac as stage0
#     sh compiler/build.sh --write-seed       also refresh seed/ from this build
#
# The C compiler is cc, or $STRATA_CC (e.g. STRATA_CC=clang).

set -eu

here=$(cd "$(dirname "$0")" && pwd)    # .../compiler
src=$here/src
lib=$here/lib
bin=$here/bin
boot=$here/build                       # stage compilers (a sibling of lib/, so they find it)
seed=$here/seed
cc=${STRATA_CC:-cc}

stage0=""
write_seed=0
while [ $# -gt 0 ]; do
    case $1 in
        --bootstrap)  [ $# -ge 2 ] || { echo "error: --bootstrap needs a path" >&2; exit 2; }
                      stage0=$2; shift 2 ;;
        --write-seed) write_seed=1; shift ;;
        *) echo "usage: sh build.sh [--bootstrap <stratac>] [--write-seed]" >&2; exit 2 ;;
    esac
done

fail() { echo "error: $*" >&2; exit 1; }
say()  { echo "$*"; }

mkdir -p "$bin" "$boot"

# --- stage0: the C seed (or the compiler given) --------------------------------
if [ -z "$stage0" ]; then
    [ -f "$seed/stratac.c" ] || fail "no C seed at $seed/stratac.c.
  Make one on a machine that has a stratac (e.g. Windows: build.ps1 -WriteSeed;
  see seed/README.md), or pass --bootstrap <stratac>."
    ver=$(cat "$seed/VERSION")
    sdir=$boot/seed-$ver
    stage0=$sdir/stratac
    if [ ! -x "$stage0" ] || [ "$seed/stratac.c" -nt "$stage0" ]; then
        say "building stage0 from the C seed (stratac $ver) ..."
        rm -rf "$sdir"
        mkdir -p "$sdir/lib"
        cp "$seed"/lib/*.h "$sdir/lib/"    # stage0 compiles against the seed's runtime
        "$cc" -std=gnu11 -O2 -w -I"$seed/lib" -I"$seed/src" "$seed/stratac.c" -o "$stage0" -lm \
            || fail "could not compile the C seed with $cc"
    fi
fi
[ -x "$stage0" ] || fail "bootstrap compiler not found: $stage0"
say "stage0: $("$stage0" version)"

# Build src/stratac.strata with compiler $2; copy the result to $3. (Each stage runs from
# its own copy, so it never overwrites the exe that is running.)
build_stage() {
    say "building $1 ..."
    "$2" build "$src/stratac.strata" >/dev/null || fail "$1 build failed"
    cp "$src/stratac" "$3"
}

# --- stage1, stage2: the compiler, built by stage0 and then by itself ----------
stage1=$boot/stage1
stage2=$boot/stage2
build_stage "stage1 (built by stage0)" "$stage0" "$stage1"
build_stage "stage2 (built by stage1)" "$stage1" "$stage2"

# --- fixpoint: stage1 and stage2 must generate the same compiler ----------------
"$stage1" emit "$src/stratac.strata" > "$boot/stage1.c" || fail "stage1 emit failed"
"$stage2" emit "$src/stratac.strata" > "$boot/stage2.c" || fail "stage2 emit failed"
cmp -s "$boot/stage1.c" "$boot/stage2.c" \
    || fail "fixpoint check FAILED: stage1 and stage2 emit different C for the compiler"
say "fixpoint ok: stage1 and stage2 emit identical C"

cp "$stage2" "$bin/stratac"
stratac=$bin/stratac

# --- console: built by the shipped compiler ------------------------------------
say "building console ..."
"$stratac" build "$src/console.strata" >/dev/null || fail "console build failed"
cp "$src/console" "$bin/console"

# --- libstrata: the compiler as a library (api/strata.toml -> bin/) -------------
say "building libstrata ..."
"$stratac" build "$here/api" >/dev/null || fail "libstrata build failed"

# --- the seed: this compiler as portable C, for the next bootstrap ----------------
version=$(sed -n 's/.*return "\([0-9][0-9.]*\).*/\1/p' "$src/version.strata")   # "1.6.0 (codename)" -> 1.6.0
if [ "$write_seed" = 1 ]; then
    mkdir -p "$seed/src" "$seed/lib"
    cp "$boot/stage2.c" "$seed/stratac.c"
    cp "$src/strata_host.h" "$seed/src/"
    rm -f "$seed"/lib/*.h
    cp "$lib"/*.h "$seed/lib/"
    printf '%s\n' "$version" > "$seed/VERSION"
    say "wrote seed/ (stratac $version)"
elif [ -f "$seed/stratac.c" ] && ! cmp -s "$boot/stage2.c" "$seed/stratac.c"; then
    say "note: seed/ is older than src/ (fine; refresh it when releasing: --write-seed)"
fi

say ""
say "artifacts in compiler/bin/ :"
for f in "$bin"/stratac "$bin"/console "$bin"/libstrata.*; do
    [ -f "$f" ] && printf '  %-18s %10s bytes\n' "$(basename "$f")" "$(wc -c < "$f" | tr -d ' ')"
done
exit 0
