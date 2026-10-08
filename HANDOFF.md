# Strata — Handoff

> The pick-up-cold guide: what Strata is, how the compiler works, how to build / test /
> release it, what exists, what's limited, and what's next. Read this first; then
> [`compiler/ARCHITECTURE.md`](compiler/ARCHITECTURE.md) (compiler internals),
> [`CHANGELOG.md`](CHANGELOG.md) (per-version detail) and
> [`website/design/DESIGN.md`](website/design/DESIGN.md) (language design).

**Current:** stratac **2.0.0** (native), released 2026-10-08
· tests **64/64** (Windows) · macOS / Linux run the C-backend subset in CI · repo **https://github.com/UseStrata/Strata**
· installed on this machine at `%LOCALAPPDATA%\Programs\strata` (on the user PATH)

**The direction (user, 2026-10-08):** Strata grows **independent** — step by step, until it
relies on nothing but the OS and what a game engine provides. 2.0 is step one: its own
x86-64 code generator and optimizer. C remains an option (`--backend c`). See §12.

---

## 1. What Strata is

A statically-typed, **compiled** language **for games and real-time software**. It compiles
to **native code itself** (x86-64 Windows: `lower → opt → x64`), or to **plain C** and then
gcc/cc (every platform; C interop). Pitch: *"safer than C, simpler than
Rust: the control C gives games, without the footguns or the borrow-checker fight."*

- **Arena / region memory**: no GC, no manual `free`. Everything in a region dies together.
- **First-class math types**: `vec2/3/4`, `mat4`, `quat`, swizzles, operators.
- **C interop**: `import <header.h>`, `link "lib"`, call C directly (C backend today).
- **Embeddable**: `libstrata.dll` + a C API, so any engine can host the compiler.
- **Self-hosted**: the compiler, `stratac`, is written in Strata and compiles itself.
  (It was bootstrapped from D--, a separate language; that code was removed in 2.0 and is
  in git history before it.)

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
│  ├─ lib/               the runtime compiled programs use (§7): C headers + srt.c (native)
│  ├─ api/               libstrata's project file + strata.h / strata.hpp / Strata.cs (§6)
│  ├─ examples/          sample programs, also the golden-test inputs (§8)
│  ├─ tests/             run.ps1 / run.sh + goldens + test projects + embedding hosts (§9)
│  └─ bin/ build/ dist/  build output, bootstrap compilers, release zips (gitignored)
├─ .github/workflows/    ci.yml: Windows (bootstrap + seed) → macOS + Linux (from that seed)
├─ editors/              VS Code + Visual Studio syntax highlighting (generated grammar)
└─ website/design/       DESIGN.md: the language design
```

---

## 3. Build, test, run, release

**Prerequisites (set up on this machine):** gcc via MSYS2 (`C:\msys64\mingw64\bin`, on PATH);
raylib via MSYS2 for the graphical examples; .NET SDK (optional, for the C# embedding test).
The D-- compiler (`C:\DMinusMinus\dec.exe`) is **no longer needed**.

```
powershell -ExecutionPolicy Bypass -File compiler\build.ps1        # bootstrap + build
powershell -ExecutionPolicy Bypass -File compiler\tests\run.ps1    # build + all 64 checks
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
stratac run    [target] [--release] [--force] [--backend b] [-- args]   # build and run
stratac build  [target] [--release] [--force] [--backend b]             # exe or dll
stratac check  [target]                                   # type-check only
stratac emit   [target]                                   # print the generated C (C backend)
stratac asm    [target] [--release]                       # print the native assembly
stratac ir     [target] [--release]                       # print the native backend's IR
stratac assemble <file.s> [out.o]                         # Strata's x86-64 assembler on its own
stratac ast | tokens <file.strata>                        # debugging views of one file
```
A *target* is a `.strata` file, a project folder, a `strata.toml`, or nothing (the project in
the current folder). A single `.strata` file builds optimized into `<name>.exe` beside it.
**Backends:** `--backend auto` (default) = native when it can (x86-64 Windows, an exe, no
C headers imported), else C; `native` / `c` force one. Native output: `<name>.o` beside
where the `.c` would go (Strata's own assembler + COFF writer), linked with `lib/srt.c` by
gcc (for now).

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
file.strata → lexer → parser → (module loader) → checker ─┬→ lower → opt → x64 → x64asm → coff .o → ld → exe   (native)
                                                          └→ codegen → C → gcc/cc → exe / dll       (C)
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
| `ir` | the native backend's IR: vregs (scalar types, ints kept sign/zero-extended to 64 bits), stack slots, labels, calls; a printer (`stratac ir`) |
| `lower` | typed AST → IR: C's arithmetic conversions (results match the C backend), vector math inline, `srt_*` runtime calls, regions, the Windows x64 struct-passing rules (`abi_*`); refuses C headers (→ C backend) |
| `opt` | fold, slot forwarding + dead stores, CSE, copy propagation, DCE, flow cleanup, LICM, coalescing; `alloc_regs` (liveness + linear scan over a target `RegSet`) |
| `x64` | IR → x86-64 GNU-as assembly, Windows x64 ABI; immediates / folded addresses ("lazy" vregs), cmp+branch fusion, stack probes |
| `x64asm` | Strata's x86-64 assembler: GNU-as AT&T text (the subset `x64` writes) → bytes, symbols, relocations (`ObjFile`); rel32 jumps always, fixups resolved in one pass |
| `coff` | writes an `ObjFile` as a Windows x64 COFF object (`.text`, `.rdata`, REL32 relocations) |
| `native` | the native driver (`native_compile`, `native_target_why`) |
| `core` | umbrella: `export import`s every phase = the compiler as a library (no `main`) |
| `project`, `build` | the build system: `strata.toml`; pipeline, cache, split builds, dll + header |
| `libstrata` | the public embedding API (`strata_*` exports) |
| `stratac`, `console`, `dump`, `version` | CLI front-end, explorer front-end, printers, version string |
| `strata_host.h` | C helpers the compiler imports: message sink (print vs capture), memory reset, lib/ lookup, one-pass string join, array free; and the OS, through `lib/crossplatform.h` (included by relative path, `static`, no Window section): `strata_host_os`, `strata_cc`, `strata_exe_path`, `strata_make_dirs`, `strata_run_argv`, parallel `strata_run_cc_parallel` |

**Key ideas**
- **Two backends, one front end.** Sugar is resolved in the checker; both `codegen` (C) and
  `lower` (IR) read the same typed AST. **Rule: every run golden must print the same
  through both** (`run.ps1` checks it). New language features need both backends (or a
  `lw_fail` in `lower` so `auto` falls back to C).
- **The native backend's runtime** is `lib/srt.c`: `srt_*` wrappers over the same headers
  the C backend uses, structs always by pointer. Adding a builtin = a `srt_*` function +
  a case in `lower_call`.
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
| `crossplatform.h` | single-header platform layer: Window, System (OS name, CPU arch, cores, exe / module path), Files (exists, is-dir, mkdir -p), Process (start / wait, no shell); per-section opt-outs, `STRATA_CROSSPLATFORM_STATIC`. **The compiler's only OS code** |
| `srt.c` | the native backend's runtime entry points (`srt_print_*`, arenas, strings, arrays, files, `srt_mat4_*` / `srt_quat_*`), compiled with each native build |

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
`abi` (native-backend corners: struct passing, 7-argument calls, narrow / unsigned
arithmetic, shifts, floats, short-circuiting, pointers).

---

## 9. Tests (`compiler/tests/run.ps1`: 64 checks; `run.sh`: the same on macOS / Linux, minus the native ones)

1. **Bootstrap + fixpoint** (runs `build.ps1`).
2. **Goldens:** `tests/<stage>/<name>.expected` vs `stratac <stage> examples/<name>.strata`,
   byte-for-byte; stages `tokens`, `ast`, `check`, `run`, `emit` (`emit` pins the generated
   C). Add a test by adding a `.expected` file.
3. **Projects:** each `tests/projects/<name>/` is run (or, for a dll, built) with `--force`
   against `expected.txt`, then must rebuild as "up to date". `native` (C sources, defines,
   per-platform libs), `lib` (dll), `multi` (split build: state + crossplatform.h across
   files), `badtoml` (project-file errors), `pure` (no C imports: a **native debug build**,
   unoptimized, of a multi-module program).
4. **Incremental:** editing one function body in a copy of `multi` recompiles one C file.
   **Backends:** every run golden again with `--backend native` (all but `interop`, which
   imports C headers) and with `--backend c`; **the assembler**: ten examples (debug +
   optimized) must disassemble (objdump) to the same instructions as GNU as's object of
   the same assembly; `stratac asm` smoke test.
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
| Native code vs gcc -O2 (2.0.0, best of 5) | vector sim 91 vs 83 ms · sieve 201 vs 156 ms · recursive fib 166 vs 78 ms |
| Native build, 20k-line single file | build + run 0.97 s (through C + gcc -O2: 3.6 s) |

---

## 11. Known limitations

- **macOS / Linux** bootstrap from `seed/` and pass `run.sh` (CI, and locally on an
  Apple Silicon Mac); the seed made on Windows is byte-identical to the C macOS emits.
  Until the seed is refreshed, stage0's builds print clang warnings (its older codegen).
- `link "x"` in a source file is not per-platform; use a project's `[windows]` /
  `[macos]` / `[linux]` sections. (`import <crossplatform.h>` links its OS library
  automatically: `os_link_args` in `build.strata`.)
- Shared libraries keep the project's name on every OS (`mathlib.so`, not
  `libmathlib.so`), so C hosts on macOS / Linux link them by path, not `-lmathlib`.
- `embed/csharp` is skipped by `run.sh` (Strata.cs not set up for macOS / Linux yet).
- **The native backend** targets x86-64 Windows only, builds exes (not dlls), and can't
  read C headers (programs importing one use the C backend). It still uses gcc to link,
  and `lib/srt.c` (C) as its runtime. No debug info yet (no
  stepping in a debugger: use `--backend c` for that). Huge functions (liveness bitsets
  over 4M words) skip register allocation. u64 ↔ float conversions of values ≥ 2^63 are
  treated as signed.
- **Needs gcc** (or cc) to build programs (check/emit/asm don't).
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
builds, hardened limits · 1.6 stratac on Windows, macOS and Linux (crossplatform.h, C seed)
· **2.0 the native backend: x86-64 code + an optimizer, Strata's own** · unreleased: Strata's
own assembler + COFF writer (no assembler program in native builds).

**The independence road (the user's chosen direction; one step at a time, C path kept):**
1. ~~**Object files directly** (COFF): an x86-64 encoder in Strata, no assembler.~~ Done
   (`x64asm.strata`, `coff.strata`; matches GNU as instruction for instruction).
2. **Strata's own linker** (PE executables, imports straight from system DLLs): no gcc
   for native builds.
3. **The runtime in Strata** (`srt.c` + `lib/*.h` → Strata modules on OS calls:
   `VirtualAlloc` / `WriteFile` on Windows, syscalls on Linux): no libc.
4. **C header import** (declarations → Strata; a small C shim for inline functions /
   code macros): raylib & engines natively.
5. **More targets**: ARM64 (the user's Apple Silicon Mac), Linux / macOS x86-64 — the IR
   is shared; each is a new `x64.strata`-like file + ABI rules.
6. **Self-compiling natively** (the compiler built by its own native backend; the C seed
   becomes optional), then **native by default for everything**; the optimizer keeps
   improving (inlining, better allocation, SIMD for vec math, tail calls).
Also: debug info (CodeView / DWARF) so native builds can be stepped in a debugger.

**Other candidates:**
1. **Tagged unions + pattern matching** (the next big language feature; pairs with `switch`).
2. **Commercial-engine integrations** (user: "later"): MSVC `.lib`, Unity / Unreal plugins;
   Godot GDExtension (M6).
3. `stratac watch` (keep the program in memory, rebuild on save) → an LSP later.
4. Language sugar: qualified names, module constants/globals, default/named args.
5. SoA / `#soa` arrays (M4), hot-reload runtime (M5).
6. Cross-platform follow-ups: publish macOS / Linux release archives (`package.sh`); make
   the Windows bootstrap use the seed too; per-platform `link`.
7. Housekeeping: bump `bootstrap.txt` (to ≥1.5.0) so the compiler's own code can use
   `break`/`continue`/modules features; clean up the D--isms in `src/` (paren conditions,
   `;`, `0 - 1`).

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
- **Keywords can't be identifiers** — e.g. `link`, `region`, `cast`, `sizeof`, `break`,
  `var` — and neither can **C keywords** (`asm`, `unsigned`, `int`, ...): the compiler's
  own C would break.
- **Bit tricks in the compiler's source:** stage0 (1.1.0) emits `1 << k` as a 32-bit C
  shift; use a 64-bit variable (`u64 one = 1; one << k`), as `opt.strata`'s `bit` does.
- **Native-backend debugging:** `stratac ir file --release` / `stratac asm file
  --release` show each stage; compare `run --backend native` against `--backend c`.
- **Benchmarks:** the first run of a freshly built exe is slowed by Windows scanning it —
  take the best of several runs.
- **Imports aren't transitive**; front-ends `import core`.
- **Don't let a compiler overwrite its own running exe** (build into another path).
- **Goldens are LF;** the test runner normalizes line endings. `emit` goldens change only
  when codegen output legitimately changes — regenerate them deliberately.
- **Shell tip (this Windows setup):** bash heredocs and inline Python strings mangle
  backslashes (`'\\'` → `'\'`, `"\n"` → a real newline, `\t` → a tab), which silently
  breaks Strata/C code and paths. Write edits containing backslashes with the editor tools.
- **Measuring memory:** short runs (< 0.1 s) are too quick for a sampling memory probe;
  judge by the larger benchmarks. The first run over freshly generated files is slowed by
  Windows file scanning — re-run warm.
- **GUI examples** open a window: build them in automation, don't run them.

---

## 14. Project facts

- **Git:** solo, linear on `main`; every version tagged `vX.Y.Z` with a GitHub Release
  carrying `strata-X.Y.Z-windows-x64.zip`. `.gitattributes` forces LF and maps `.strata`
  to C for GitHub highlighting.
- **Versioning:** SemVer; 1.0.0 = self-hosting; 2.0.0 = the native backend (the user's
  call); minor bumps are fine (the user: nobody depends on it yet).
- **Licensing:** GPL-3.0 compiler; runtime linking exception on `lib/` (programs built
  with Strata are the author's); embedding exception on libstrata + `compiler/api/`;
  commercial license ($100 intro) for private compiler modifications, enabled by the CLA.
  Both exceptions are marked for legal review. "Strata™" is a common-law trademark.
