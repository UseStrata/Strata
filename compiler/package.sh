#!/bin/sh
# package.sh - build a distributable Strata toolchain archive on macOS / Linux, the
# counterpart of package.ps1: compiler/dist/strata-<version>-<os>-<arch>.tar.gz, laid out
# like an install (stratac finds lib/ next to itself).
#
#   sh compiler/package.sh 1.6.0

set -eu
here=$(cd "$(dirname "$0")" && pwd)    # .../compiler
repo=$(dirname "$here")
version=${1:-dev}
case $(uname -s) in Darwin) os=macos ;; Linux) os=linux ;; *) os=$(uname -s | tr 'A-Z' 'a-z') ;; esac
arch=$(uname -m)
case $arch in x86_64|amd64) arch=x64 ;; aarch64) arch=arm64 ;; esac

echo "building ..."
sh "$here/build.sh" >/dev/null

stage=$(mktemp -d)/strata
mkdir -p "$stage/lib" "$stage/include"
for f in stratac console libstrata.dylib libstrata.so libstrata.h; do
    if [ -f "$here/bin/$f" ]; then cp "$here/bin/$f" "$stage/"; fi
done
cp "$here"/lib/*.h "$here"/lib/srt.strata "$here"/lib/CrossPlatform.strata "$stage/lib/"
cp -R "$here"/lib/CrossPlatform "$here"/lib/srt "$stage/lib/"
for f in strata.h strata.hpp Strata.cs; do cp "$here/api/$f" "$stage/include/"; done
for f in LICENSE LICENSE-RUNTIME.md LICENSE-EMBEDDING.md README.md CHANGELOG.md; do
    if [ -f "$repo/$f" ]; then cp "$repo/$f" "$stage/"; fi
done

mkdir -p "$here/dist"
out=$here/dist/strata-$version-$os-$arch.tar.gz
tar -czf "$out" -C "$(dirname "$stage")" strata
rm -rf "$(dirname "$stage")"
echo ""
echo "packaged: $out"
echo "note: the compiler runs a C compiler (cc, or \$STRATA_CC) to build programs."
