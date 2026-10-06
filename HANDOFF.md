# Strata — Handoff

> The pick-up-cold guide: what Strata is, how the compiler works, how to build / test /
> release it, what exists, what's limited, and what's next. Read this first; then
> [`compiler/ARCHITECTURE.md`](compiler/ARCHITECTURE.md) (compiler internals),
> [`CHANGELOG.md`](CHANGELOG.md) (per-version detail) and
> [`website/design/DESIGN.md`](website/design/DESIGN.md) (language design).

**Current:** stratac **1.6.0** (cross-platform) · tests **58** (1.6.0: awaiting its first CI run on Windows / macOS / Linux) · repo **https://github.com/UseStrata/Strata**
· installed on this machine at `%LOCALAPPDATA%\Programs\strata` (on the user PATH)

---

## 1. What Strata is

A statically-typed, **compiled** language **for games and real-time software**. It compiles
to **plain C**, then to a native binary with gcc. Pitch: *"safer than C, simpler than
Rust: the control C gives games, without the footguns or the borrow-checker fight."*

- **Arena / region memory**: no GC, no manual `free`. Everything in a region dies together.
- **First-class math types**: `vec2/3/4`, `mat4`, `quat`, swizzles, operators.
- **C interop**: it *is* C underneath: `import <header.h>`, `link "lib"`, call C directly.
- **Embeddable**: `libstrata.dll` + a C API, so any engine can host the compiler.
- **Self-hosted**: the compiler, `stratac`, is written in Strata and compiles itself.
  (It was bootstrapped from D--, a separate language; that code is in `archive/`.)

---

## 2. Repository layout

```
Strata/
├─ HANDOFF.md  README.md  CHANGELOG.md  Strata.md (founding plan)
├─ LICENSE (GPL-3.0)  LICENSE-RUNTIME.md  LICENSE-EMBEDDING.md  COMMERCIAL.md  CLA.md  TRADEMARK.md
├─ compiler/
│  ├─ ARCHITECTURE.md    compiler internals (read before touching src/)
│  ├─ build.ps1          bootstrap + build bin/stratac.exe, console.exe, libstrata.dll
│  ├─ build.sh           the same on macOS / Linux, from seed/ (stratac, console, libstrata.dylib/.so)
│  ├─ bootstrap.txt      the release version the Windows build bootstraps from (currently 1.1.0)
│  ├─ seed/              the C seed: a stratac compiled to C + its headers (macOS / Linux stage0)
│  ├─ install.ps1/.sh    install (Windows: %LOCALAPPDATA%\Programs\strata + PATH; else ~/.local)
│  ├─ package.ps1/.sh    release zip / tar.gz into dist/
│  ├─ src/               THE COMPILER, in Strata (§4)
│  ├─ lib/               the C runtime compiled programs use (§7)
│  ├─ api/               libstrata's project file + strata.h / strata.hpp / Strata.cs (§6)
│  ├─ examples/          sample programs, also the golden-test inputs (§8)
│  ├─ tests/             run.ps1 / run.sh + goldens + test projects + embedding hosts (§9)
│  └─ bin/ build/ dist/  build output, bootstrap compilers, release zips (gitignored)
├─ .github/workflows/    ci.yml: Windows (bootstrap + seed) → macOS + Linux (from that seed)
├─ editors/              VS Code + Visual Studio syntax highlighting (generated grammar)
├─ website/design/       DESIGN.md: the language design
└─ archive/              retired: the D-- compiler + D--→Strata translator (see its README)
```

---

## 3. Build, test, run, release

**Prerequisites (set up on this machine):** gcc via MSYS2 (`C:\msys64\mingw64\bin`, on PATH);
raylib via MSYS2 for the graphical examples; .NET SDK (optional, for the C# embedding test).
The D-- compiler (`C:\DMinusMinus\dec.exe`) is **no longer needed**.

```
powershell -ExecutionPolicy Bypass -File compiler\build.ps1        # bootstrap + build
powershell -ExecutionPolicy Bypass -File compiler\tests\run.ps1    # build + all 58 checks
powershell -ExecutionPolicy Bypass -File compiler\install.ps1      # rebuild + install globally
```

**The bootstrap** (`build.ps1`): stage0 = the release named in `bootstrap.txt`, downloaded
from GitHub once and cached in `compiler/build/` (`-Bootstrap <exe>` overrides; offline it
falls back to the installed `stratac`). stage0 builds `src/stratac.strata` → stage1; stage1
builds it again → stage2. **The build fails unless stage1 and stage2 emit byte-identical C**
(the fixpoint). stage2 ships as `bin/stratac.exe`; `console.exe` is built by it;
`libstrata.dll` is built from `compiler/api/strata.toml`.

**macOS / Linux** (needs `cc`; X11 headers on Linux for the test projects):
```
sh compiler/build.sh            # stage0 = seed/stratac.c compiled with cc, then stage1 → stage2
sh compiler/tests/run.sh        # build + the same checks as run.ps1
sh compiler/install.sh          # ~/.local/share/strata, linked as ~/.local/bin/stratac
```
`build.sh --bootstrap <stratac>` uses another stage0; `--write-seed` (and `build.ps1
-WriteSeed`) refreshes `seed/` from the build. The seed is the compiler's own C (the
fixpoint output) plus the `strata_host.h` and `lib/*.h` it was made against, so it is the
same on every OS and keeps compiling whatever `src/` becomes. **The first seed must come
from Windows** (a 1.6.0+ compiler: the releases are Windows-only). CI makes one on every
push and bootstraps macOS / Linux from it; on `main`, when `seed/VERSION` isn't the
compiler's version yet, CI commits the new seed back (so each version gets one seed).

**Quick iteration on the compiler:** `compiler\bin\stratac.exe build compiler\src\stratac.strata`
→ `src\stratac.exe` (don't make a compiler overwrite its own running exe). Run the full
`run.ps1` before committing.

**Using the compiler:**
```
stratac new    <name>                                     # project: strata.toml + src/main.strata
stratac run    [target] [--release] [--force] [-- args]   # build and run
stratac build  [target] [--release] [--force]             # exe or dll
stratac check  [target]                                   # type-check only
stratac emit   [target]                                   # print the generated C
stratac ast | tokens <file.strata>                        # debugging views of one file
```
A *target* is a `.strata` file, a project folder, a `strata.toml`, or nothing (the project in
the current folder). A single `.strata` file builds `-O2` into `<name>.exe` beside it.

**Projects (`strata.toml`)** — every key is documented at the top of `src/project.strata`:
`[project]` name / entry / output (`exe`|`dll`) / out_dir; `[build]` defines, include_dirs,
lib_dirs, libs, c_sources, release, split; `[windows]`/`[linux]`/`[macos]` per-platform libs.
Project builds are **incremental and parallel** (§4, "Split builds").

**Releasing a version** (the established process):
1. Bump `export string stratac_version()` in `compiler/src/version.strata` (and
   `editors/vscode/package.json`); add a `CHANGELOG.md` section; update this file.
2. `run.ps1` must pass. Refresh the seed (`build.ps1 -WriteSeed`) and commit it with the
   release. Commit to `main`, tag `vX.Y.Z`.
3. Verify from a clean checkout: `git worktree add <tmp> vX.Y.Z`, run its `run.ps1`, then
   `package.ps1 -Version X.Y.Z` there (so the zip's binaries match the tag).
4. `git push origin main vX.Y.Z`; `gh release create vX.Y.Z <zip> --title ... --notes ...`.
5. `install.ps1 -NoBuild` to update the machine's global `stratac`.

---

## 4. How the compiler works

A strict one-way pipeline, one file per phase, phases talking only through data:

```
file.strata → lexer → parser → (module loader) → checker → codegen → C → gcc → exe / dll
```

| `compiler/src/` | Role |
|---|---|
| `token`, `ast` | shared data: tokens; AST nodes (`TypeNode`/`Expr`/`Stmt`/`Decl`), `Module`, `Program` |
| `lexer` | text → tokens. Newlines end statements (not inside `(`/`[`); `;` optional. Interns identifiers |
| `parser` | tokens → AST, recursive descent; nesting limit (`max_nesting`, 1,000) |
| `modules` | the loader: parses each imported file once → one `Program` + module table |
| `hashidx` | a small hash index (checker name tables, lexer interning) — Strata has no map type yet |
| `checker` | names + module visibility, types, `var` inference; writes each expr's type to `Expr.rtype` |
| `codegen` | typed AST → C (one file, or split per module chunk); reads `rtype` for operator lowering |
| `core` | umbrella: `export import`s every phase = the compiler as a library (no `main`) |
| `project`, `build` | the build system: `strata.toml`; pipeline, cache, split builds, dll + header |
| `libstrata` | the public embedding API (`strata_*` exports) |
| `stratac`, `console`, `dump`, `version` | CLI front-end, explorer front-end, printers, version string |
| `strata_host.h` | C helpers the compiler imports: message sink (print vs capture), memory reset, lib/ lookup, one-pass string join, array free; and the OS, through `lib/crossplatform.h` (included by relative path, `static`, no Window section): `strata_host_os`, `strata_cc`, `strata_exe_path`, `strata_make_dirs`, `strata_run_argv`, parallel `strata_run_cc_parallel` |

**Key ideas**
- **Everything lowers to plain C**; sugar is resolved in the checker, gone by codegen.
- **`Expr.rtype`**: codegen picks C from the checked types (`a + b` → `vec3_add(a, b)`,
  `.` vs `->`, element casts for dynamic arrays). Named result types share one node each.
- **Modules** are parsed per file; every `Decl` records its module. The checker enforces
  visibility and gives **colliding private names** module-prefixed C names
  (`mods_shapes__helper`).
- **Split builds** (projects, default): a shared header with all types, then module
  **chunks** (~2 per core) as separate C files. Each file declares only the exports of the
  modules it imports, so editing a body recompiles one chunk and changing an export
  recompiles only its importers. gcc runs in parallel, started directly with response files.
  Runtime state is defined once, in the main module's file (`lib/sstate.h`).
  `split = false` gives one C file (libstrata needs that: `strata_host.h` keeps `static`s).
- **Messages** go through `strata_report` (printed by the CLI, captured by libstrata).
- **Performance rules learned the hard way:** never build strings with `s = s + x` in a
  loop (quadratic) — collect pieces and `strata_join` / `join_with`; walk left-deep
  operator chains in a loop, not recursively; long strings made by the runtime have their
  length remembered (`lib/sstr.h`), so `.len` / `substr` on them are O(1).

---

## 5. The language today

**Feel:** types-first (C#-like), `var` inference, braces, paren-free control flow, newlines
end statements (`;` optional). Files: `.strata` (or `.str`).

```strata
struct Entity { vec3 pos; int hp }
enum State { Idle, Walk, Jump }
export int add(int a, int b) { return a + b }      // export: visible to importers
var x = 5
vec3 v = vec3(1, 0, 0) * 2.0
for i in 0..10 { if i % 2 == 0 { continue }; print(i) }
```

- **Types:** `int` (64-bit), `float` (32-bit), `bool`, `char`, `string` (a C `const char*`),
  sized `i8..u64`/`f32`/`f64`, `vec2/3/4`, `mat4`, `quat`, structs, enums, pointers `T*`,
  dynamic arrays `T[dynamic]` (literals, `.push`, `.len`, indexing, `for x in xs`).
- **Control flow:** `if`/`else`, `while`, `for i in a..b`, `for x in array`,
  `break`/`continue` (a `break` in a `switch` leaves the loop), `switch` (no fall-through,
  `case A, B:`, `default:`).
- **Memory:** `world = arena()` + `world.new(T)`, `region name { ... }` (freed at the end, and
  on `break`/`continue`/`return`), `alloc(value)` (global heap), `null`; `.` auto-derefs.
- **Math:** vector/matrix/quaternion operators, swizzles (`v.xy`), `dot`, `cross`, `length`,
  `normalize`, `mat4_*`, `quat_*`; prelude `min`, `max`, `clamp`, `lerp`, `PI`.
- **Strings & I/O:** `+`, `.len`, `==`, `s[i]`, `substr`, `int_to_str`, `cstr`,
  `read_file`, `write_file`, `args()`.
- **Casts:** `cast<T>(x)` (scalar↔scalar, pointer↔pointer, pointer↔int), `sizeof(T)`.
- **Modules:** every file is a module; declarations are **private unless `export`ed**.
  `import gfx.Renderer` loads `<root>/gfx/Renderer.strata` (root = the main file's folder);
  imports are **not transitive**; `export import X` re-exports. Modules hold declarations
  only. Missing/private/unimported/conflicting names get errors that say how to fix them.
- **C interop:** `import <x.h>` / `import "x.h"`, `link "lib"`; unknown names resolve as C
  once a header is imported. Single-header C libraries can check `STRATA_PROGRAM` to
  compile their implementation (see `lib/crossplatform.h`).
- **Designed, not built:** tagged unions + pattern matching, expression-bodied functions,
  default/named arguments, qualified names (`shapes.area`), module-level constants /
  globals, region-escape checking.

---

## 6. Embedding (engines, editors, tools)

`libstrata.dll` + `compiler/api/strata.h` (C), `strata.hpp` (C++), `Strata.cs` (C#,
P/Invoke). Installed to `<prefix>/include/` with `libstrata.dll.a`. **Any engine may embed
it under any license** (`LICENSE-EMBEDDING.md`, the Classpath exception).

API: `strata_check` / `strata_check_source` (unsaved editor text), `strata_emit(_source)`,
`strata_build` / `strata_output_path`, `strata_diagnostics` (messages are captured),
`strata_set_libdir` (default: `lib/` next to the dll), `strata_reset` (frees all compiler
memory: engines can recompile indefinitely), `strata_version`. Not thread-safe.

A Strata project with `output = "dll"` exports exactly its entry module's `export`ed
functions and gets a generated `<name>.h` + `<name>.dll.a` beside the dll.

---

## 7. The runtime (`compiler/lib/`, header-only C; GPL + runtime linking exception)

| File | Provides |
|---|---|
| `arena.h` | arenas / regions; the global heap for `alloc` |
| `sstr.h` | strings: concat, eq, len, substr, int_to_str; remembers long strings' lengths |
| `sarr.h` | dynamic arrays (tracked so a host can free them all) |
| `sio.h` | `read_file`, `write_file`, `args()` |
| `smath.h` / `sprelude.h` | vectors, matrices, quaternions / min, max, clamp, lerp, PI |
| `sstate.h` | `STRATA_STATE`: runtime state is `static`, or shared across a split build's files |
| `crossplatform.h` | single-header platform layer: Window, System (OS name, cores, exe / module path), Files (exists, is-dir, mkdir -p), Process (start / wait, no shell); per-section opt-outs, `STRATA_CROSSPLATFORM_STATIC`. **The compiler's only OS code** |

**Rule:** the bootstrap release compiles the compiler against *its own* older `lib/`. So a
new runtime function the compiler uses must be guarded (`#ifdef STRATA_ARR_TRACKED`,
`STRATA_STR_LEN_CACHE`) or live in `src/strata_host.h` instead. (`crossplatform.h` is the
exception: `strata_host.h` includes it as `"../lib/crossplatform.h"`, i.e. from this repo.)

---

## 8. Examples (`compiler/examples/`)

`hello` (flagship), `run1`, `arena`, `vectors`, `matrix`, `arrays`, `switch`, `strings`,
`interop`, `list` (alloc + null), `casts`, `prelude`, `loops` (break/continue),
`modules` + `greetlib`, `modules2` + `mods/` (the module system), `crossplatform` (a window
via `lib/crossplatform.h`). Graphical (open a window; build, don't auto-run): `window`,
`sprite`, `balls`. Error cases: `errors`, `breakerr`, `modvis`, `modload`, `modpriv`.

---

## 9. Tests (`compiler/tests/run.ps1`: 58 checks; `run.sh`: the same on macOS / Linux)

1. **Bootstrap + fixpoint** (runs `build.ps1`).
2. **Goldens:** `tests/<stage>/<name>.expected` vs `stratac <stage> examples/<name>.strata`,
   byte-for-byte; stages `tokens`, `ast`, `check`, `run`, `emit` (`emit` pins the generated
   C). Add a test by adding a `.expected` file.
3. **Projects:** each `tests/projects/<name>/` is run (or, for a dll, built) with `--force`
   against `expected.txt`, then must rebuild as "up to date". `native` (C sources, defines,
   per-platform libs), `lib` (dll), `multi` (split build: state + crossplatform.h across
   files), `badtoml` (project-file errors).
4. **Incremental:** editing one function body in a copy of `multi` recompiles one C file.
5. **Embedding** (`tests/embed/`): C, C++, C# hosts using libstrata (incl. 300
   compile+reset cycles with flat memory), and a C host calling a Strata-built dll.
6. **Performance & limits:** 20k lines must check in < 3 s; 1,001-deep nesting must be a
   clean error; a 100,000-term expression must compile quickly.

---

## 10. Capacity (measured 2026-09-26, v1.5.0, 28-core Windows machine)

| What | Result |
|---|---|
| Program size | linear: 1,000,000 lines check in 1.1 s / 1.1 GB; emit in 3.1 s / 1.6 GB |
| Modules | 20,000 modules check in 1.1 s (warm; a first read of thousands of new files is slow — Windows scans them) |
| 81k-line project | check 0.14 s / 92 MB; full debug build 4.1 s; release 4.9 s; edit one function → 1.0 s |
| 250k-line, 1,001-module project | full debug build 13.1 s; nothing changed 1.5 s; edit one function 2.4 s |
| Nesting (parens, calls, blocks, unary) | 1,000 levels; deeper is a clean error (safe on a 1 MB thread stack) |
| Operator chains / strings / arrays | 1,000,000-term expression 0.8 s; 10 MB string 0.28 s; 1,000,000-item array 1.4 s |

---

## 11. Known limitations

- **macOS / Linux are written but not yet run end to end:** they need the first C seed
  (made on Windows, or by CI). `crossplatform.h` and `strata_host.h` are tested on macOS;
  the Windows branches are unchanged in behaviour but only compile-checked by CI.
- `link "user32"` in a source file is not per-platform (`examples/crossplatform.strata`
  builds only on Windows); use a project's `[windows]` / `[macos]` / `[linux]` sections.
- Shared libraries keep the project's name on every OS (`mathlib.so`, not
  `libmathlib.so`), so C hosts on macOS / Linux link them by path, not `-lmathlib`.
- `embed/csharp` is skipped by `run.sh` (Strata.cs not set up for macOS / Linux yet).
- **Needs gcc** to build programs (check/emit don't). Bundling tcc is planned.
- **Build cache** doesn't track C headers your program `import`s — use `--force` after
  editing one.
- **`link "x"`** only produces `-lx`; library paths / flags / frameworks need a `strata.toml`.
- **MSVC-based engines** can load `libstrata.dll` at runtime but not link it (no `.lib` yet).
- **libstrata** is single-threaded.
- **Strings** are NUL-terminated C strings: no `\0` inside a string.
- **`for i in 0..n`** re-evaluates `n` each iteration (a semantics decision is pending).
- **No globals / module constants**; top-level `const` is a local of `main`.
- **Memory** is mostly the AST (`Expr` 104 B, `Stmt` 184 B); arenas never free early.

---

## 12. What's next (and open decisions)

**Done this era (see CHANGELOG):** 1.0 self-hosting · 1.1 module system · 1.2 build system
· 1.3 embedding API · 1.4 compiler 25–540× faster · 1.5 break/continue, incremental parallel
builds, hardened limits · 1.6 stratac on Windows, macOS and Linux (crossplatform.h, C seed).

**Candidates, roughly in value order:**
1. **Bundle tcc** for debug builds (near-instant; removes the gcc requirement for `run`).
   gcc start-up (~150 ms per C file on Windows) is now most of a build.
2. **Tagged unions + pattern matching** (the next big language feature; pairs with `switch`).
3. **Commercial-engine integrations** (user: "later"): MSVC `.lib`, Unity / Unreal plugins;
   Godot GDExtension (M6).
4. `stratac watch` (keep the program in memory, rebuild on save) → an LSP later.
5. Language sugar: qualified names, module constants/globals, default/named args.
6. SoA / `#soa` arrays (M4), hot-reload runtime (M5).
7. Cross-platform follow-ups: commit the first seed (from CI or `build.ps1 -WriteSeed`);
   publish macOS / Linux release archives (`package.sh`); make the Windows bootstrap use
   the seed too (then releases needn't be downloaded at all); per-platform `link`.
8. Housekeeping: bump `bootstrap.txt` (to ≥1.5.0) so the compiler's own code can use
   `break`/`continue`/modules features; clean up the D--isms in `src/` (paren conditions,
   `;`, `0 - 1`); delete `archive/` if the D-- path is no longer wanted (user's call).

**Open decisions for the user:** does `for i in 0..n` evaluate `n` once (Go/Rust) or each
iteration (today)? · which of the candidates comes next.

---

## 13. Working notes (for whoever picks this up — human or agent)

- **The bootstrap rule:** the compiler's own source may only use features of the release in
  `bootstrap.txt` **and of the seed** (`seed/VERSION`). To use a new feature in `src/`:
  release a version with it, bump the pin, refresh the seed.
- **OS-specific code goes in `lib/crossplatform.h`** (a new section or function), called
  from `src/strata_host.h`. No `system()`, `cmd.exe`, `.exe` literals or `#ifdef _WIN32`
  in the Strata sources: ask `host_os()` / `exe_ext()` / `dll_ext()`.
- **Edit `compiler/src/*.strata` directly.** `src/strata_host.h` is compiled from the repo,
  so new C helpers the compiler needs belong there (not in `lib/`, see §7).
- **Keywords can't be identifiers** — e.g. `link`, `region`, `cast`, `sizeof`, `break`.
- **Imports aren't transitive**; front-ends `import core`.
- **Don't let a compiler overwrite its own running exe** (build into another path).
- **Goldens are LF;** the test runner normalizes line endings. `emit` goldens change only
  when codegen output legitimately changes — regenerate them deliberately.
- **Shell tip (this Windows setup):** bash heredocs and inline Python strings mangle
  backslashes (`'\\'` → `'\'`), which silently breaks Strata/C code. Write multi-line edits
  with a file-based script or the editor tools.
- **Deleting tracked directories** may be blocked by the permission system; move to
  `archive/` with `git mv` and let the user delete.
- **Measuring memory:** short runs (< 0.1 s) are too quick for a sampling memory probe;
  judge by the larger benchmarks. The first run over freshly generated files is slowed by
  Windows file scanning — re-run warm.
- **GUI examples** open a window: build them in automation, don't run them.

---

## 14. Project facts

- **Git:** solo, linear on `main`; every version tagged `vX.Y.Z` with a GitHub Release
  carrying `strata-X.Y.Z-windows-x64.zip`. `.gitattributes` forces LF and maps `.strata`
  to C for GitHub highlighting.
- **Versioning:** SemVer; 1.0.0 = self-hosting; minor bumps are fine (the user: nobody
  depends on it yet).
- **Licensing:** GPL-3.0 compiler; runtime linking exception on `lib/` (programs built
  with Strata are the author's); embedding exception on libstrata + `compiler/api/`;
  commercial license ($100 intro) for private compiler modifications, enabled by the CLA.
  Both exceptions are marked for legal review. "Strata™" is a common-law trademark.
