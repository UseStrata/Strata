# Strata syntax highlighting (VS Code)

Syntax coloring for `.strata` / `.str` files: keywords, primitive and user types, `cast<T>`
and `sizeof(T)`, `import` (modules and C headers) and `link`, strings with escapes,
chars, numbers (hex, binary, `_` separators, floats), nested `/* */` comments, built-in
functions (`print`, `alloc`, `substr`, vector math, ...), function names, and the `..` range.

Also provides comment toggling, bracket matching, auto-closing pairs and indentation.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File editors\vscode\install.ps1    # Windows
```
```sh
sh editors/vscode/install.sh                                         # macOS / Linux
```

This copies the extension to `~/.vscode/extensions/strata` (`%USERPROFILE%` on Windows; no
admin needed). PowerShell 7 on any OS can also run `pwsh editors/vscode/install.ps1`.
Then run **Developer: Reload Window** and open any `.strata` file; the language indicator
in the bottom-right should read **Strata**.

## Notes

- Highlighting only, no IntelliSense or diagnostics yet. `stratac check <file.strata>`
  gives type errors from the command line.
- The grammar is **generated**: edit `editors/build_grammar.py`, run
  `python editors/build_grammar.py`, then re-run the installer.
- User types are recognized from how they are used (`Entity e`, `Node* next`,
  `Ball[dynamic] bs`, `Entity{...}`, `struct Entity`) because a grammar can't see
  declarations. Write pointer types with the `*` attached (`Node* n`), as the Strata sources
  do; a spaced `a * b` is read as multiplication.
