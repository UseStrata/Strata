# SPDX-License-Identifier: GPL-3.0-only
# Copyright © 2026 Connor Rutberg
#
# Installs Strata syntax highlighting into VS Code (per-user, no admin needed):
#     powershell -ExecutionPolicy Bypass -File editors\vscode\install.ps1    (Windows)
#     pwsh editors/vscode/install.ps1                                         (PowerShell 7, any OS)
#     sh editors/vscode/install.sh                                            (macOS / Linux)
#
# Copies this folder to ~/.vscode/extensions/strata (%USERPROFILE% on Windows). Safe to
# re-run (do so after regenerating the grammar), then run "Developer: Reload Window" in
# VS Code.

$ErrorActionPreference = 'Stop'
$src  = $PSScriptRoot
$dest = [IO.Path]::Combine($HOME, '.vscode', 'extensions', 'strata')   # $HOME: every OS and PowerShell

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($item in 'package.json', 'language-configuration.json', 'README.md', 'syntaxes') {
    Copy-Item (Join-Path $src $item) $dest -Recurse -Force
}
Write-Host "installed -> $dest"
Write-Host "Reload VS Code (Developer: Reload Window), then open a .strata file."
