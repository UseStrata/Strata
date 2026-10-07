#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright © 2026 Connor Rutberg
#
# Installs Strata syntax highlighting into VS Code on macOS / Linux (per-user):
#     sh editors/vscode/install.sh
# (Windows: install.ps1.) Copies this folder to ~/.vscode/extensions/strata. Safe to
# re-run (do so after regenerating the grammar), then run "Developer: Reload Window".

set -eu
src=$(cd "$(dirname "$0")" && pwd)
dest=$HOME/.vscode/extensions/strata

rm -rf "$dest"
mkdir -p "$dest"
for item in package.json language-configuration.json README.md syntaxes; do
    cp -R "$src/$item" "$dest/"
done
echo "installed -> $dest"
echo "Reload VS Code (Developer: Reload Window), then open a .strata file."
