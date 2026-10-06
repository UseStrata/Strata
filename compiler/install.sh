#!/bin/sh
# install.sh - install (or update) the Strata toolchain on macOS / Linux, the way a C
# compiler lives on a system: stratac + console + libstrata and the lib/ runtime in one
# folder, with stratac linked into a bin folder on PATH. (Windows: install.ps1.)
# Re-run any time to update.
#
#   sh compiler/install.sh                          # ~/.local/share/strata, links in ~/.local/bin
#   sh compiler/install.sh --prefix /opt/strata --bindir /usr/local/bin
#   sh compiler/install.sh --no-build               # install what's already in bin/
#   sh compiler/install.sh --uninstall
#
# Installed layout:  <prefix>/stratac  <prefix>/console  <prefix>/libstrata.dylib|.so
#                    <prefix>/lib/...       the runtime headers
#                    <prefix>/include/...   the embedding API (strata.h, strata.hpp, Strata.cs)
#                    <bindir>/stratac  ->  <prefix>/stratac
# stratac finds its lib/ next to its real (symlink-resolved) path, so nothing else needs
# configuring. This script never edits your shell profile; it tells you if bindir isn't
# on PATH.

set -eu

compiler=$(cd "$(dirname "$0")" && pwd)
bin=$compiler/bin
prefix=${XDG_DATA_HOME:-$HOME/.local/share}/strata
bindir=$HOME/.local/bin
uninstall=0
build=1
while [ $# -gt 0 ]; do
    case $1 in
        --prefix)    prefix=$2; shift 2 ;;
        --bindir)    bindir=$2; shift 2 ;;
        --uninstall) uninstall=1; shift ;;
        --no-build)  build=0; shift ;;
        *) echo "usage: sh install.sh [--prefix <dir>] [--bindir <dir>] [--no-build] [--uninstall]" >&2; exit 2 ;;
    esac
done

# --- Uninstall --------------------------------------------------------------
if [ $uninstall -eq 1 ]; then
    for l in stratac strata-console; do
        if [ -L "$bindir/$l" ]; then rm -f "$bindir/$l"; echo "removed $bindir/$l"; fi
    done
    if [ -d "$prefix" ]; then rm -rf "$prefix"; echo "removed $prefix"; fi
    exit 0
fi

# --- Build the artifacts (unless --no-build) ----------------------------------
if [ $build -eq 1 ]; then
    echo "building artifacts via build.sh ..."
    sh "$compiler/build.sh"
fi
[ -x "$bin/stratac" ] || { echo "error: stratac not found in bin/; run build.sh first" >&2; exit 1; }

# --- Copy into the shared location ------------------------------------------
echo "installing to $prefix ..."
mkdir -p "$prefix/include"
for a in stratac console libstrata.dylib libstrata.so libstrata.h; do
    if [ -f "$bin/$a" ]; then cp "$bin/$a" "$prefix/$a"; fi
done
for f in strata.h strata.hpp Strata.cs; do
    if [ -f "$compiler/api/$f" ]; then cp "$compiler/api/$f" "$prefix/include/$f"; fi
done
rm -rf "$prefix/lib"                                  # drop stale runtime files
mkdir -p "$prefix/lib"
cp "$compiler"/lib/*.h "$prefix/lib/"

# --- Link into bindir ---------------------------------------------------------
mkdir -p "$bindir"
ln -sf "$prefix/stratac" "$bindir/stratac"
ln -sf "$prefix/console" "$bindir/strata-console"

# --- Report -----------------------------------------------------------------
echo ""
echo "installed: $prefix/stratac  (linked as $bindir/stratac)"
echo "runtime:   $prefix/lib"
case ":$PATH:" in
    *":$bindir:"*) ;;
    *) echo ""
       echo "NOTE: $bindir is not on PATH. Add it in your shell profile, e.g.:"
       echo "      export PATH=\"$bindir:\$PATH\"" ;;
esac
if ! command -v "${STRATA_CC:-cc}" >/dev/null 2>&1; then
    echo ""
    echo "NOTE: building programs needs a C compiler ('cc', or set STRATA_CC)."
    echo "      macOS: xcode-select --install    Debian/Ubuntu: sudo apt install build-essential"
fi
echo ""
echo "Done. Then:  stratac run <file.strata>"
