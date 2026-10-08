# Changelog

All notable changes to Strata are recorded here. Versions follow
[Semantic Versioning](https://semver.org/). Each version has a matching `vX.Y.Z` git tag
and a GitHub Release.

## [2.1.0] - 2026-10-08
**Native builds need no C compiler.** Strata now compiles, assembles and links a program
itself: from `.strata` source to a Windows `.exe` with nothing but `stratac` and
Windows' own DLLs.

### Added
- **Strata's own linker** (`src/pelink.strata`): COFF objects -> a Windows x64 PE
  executable. It merges sections (`.text` / `.rdata` / `.data` / `.bss`), resolves
  symbols, applies relocations (REL32 and +1..5, ADDR64, ADDR32NB, ADDR32), and resolves
  what's left by reading the **export tables of the system DLLs themselves**
  (`msvcrt.dll`, `kernel32.dll`): no import libraries. Calls to imports go through jump
  stubs; `__imp_` references use the import address table directly. A small startup
  stub (Strata's own, assembled by its assembler) gets `argc` / `argv` from msvcrt,
  calls `main` and exits through msvcrt's `exit`.
  - `lib/srt.o`: the runtime compiled once, by `build.ps1`, and shipped in releases. It
    calls only what `msvcrt.dll` exports: it now formats integers and floats itself
    (float output stays byte-identical to the C backend's `%g`).
  - A program builds in 62 ms (through C and gcc: 308 ms); the 20k-line one in 0.47 s
    (was 0.87 s). Executables are small (12 KB for the examples) and import only
    `msvcrt.dll`.
  - Programs that link C libraries (`link`, `libs`, `c_sources`, crossplatform.h's OS
    library) are still linked by the C toolchain; so is everything if `lib/srt.o` is
    missing. If Strata's linker ever fails, `--backend auto` falls back to it too.
- **Strata's own x86-64 assembler** (`src/x64asm.strata`) and **COFF object writer**
  (`src/coff.strata`): native builds no longer run an assembler. The backend's assembly
  becomes machine code inside `stratac` and is written as a Windows object file
  (`<name>.o`). It encodes every
  instruction form the backend uses (moves and extensions, integer ALU, multiply /
  divide, shifts, setcc, jumps / calls with 32-bit displacements, push / pop, SSE scalar
  arithmetic, compares and conversions), `.text` / `.rdata`, `.globl`, `.p2align`,
  `.asciz`, `.float` / `.double`, and relocations (REL32, against sections or external
  symbols, with the >65535-relocation overflow form).
  - Verified against GNU as: across every example (debug and optimized) plus a
    20k-line program - 414,234 instructions - the object files disassemble to the same
    instructions with the same relocations. It assembles that 3.4 MB of assembly in
    157 ms (GNU as: 232 ms); the 20k-line native build went from 0.97 to 0.87 s.
- `stratac assemble <file.s> [out.o]`: the assembler on its own.
- Tests (65): the assembler's output vs GNU as's, instruction by instruction, for ten
  examples in both modes (needs objdump; skipped without it); native builds with **no
  gcc on PATH** (four examples and the `pure` project).

### Changed
- If the assembler ever rejects the backend's output, `--backend auto` builds with C
  instead (and `--backend native` reports it as an internal error).
- `build.ps1` also builds `lib/srt.o`; `package.ps1` ships it.

## [2.0.0] - 2026-10-08
The first step toward a Strata that depends on nothing but the operating system: it now
compiles programs to **x86-64 machine code itself**, with its own optimizer. C stays
available as a backend.

### Added
- **The native backend** (x86-64, Windows): Strata's own code generator. Programs no
  longer go through C: the compiler writes the assembly itself.
  - `src/ir.strata`: an intermediate representation (virtual registers, labels,
    loads / stores, calls) that every future architecture shares.
  - `src/lower.strata`: the checked program -> IR, with C's arithmetic conversions (so
    programs print exactly what the C backend's builds print) and the Windows x64
    calling convention (structs of 1/2/4/8 bytes in registers, others by pointer,
    hidden result pointers), so Strata functions call and are callable from C.
  - `src/opt.strata`: **the optimizer** - constant folding, copy propagation,
    store-to-load forwarding through private stack slots (vector math stays in
    registers), common subexpressions, loop-invariant code motion, dead code and
    control-flow cleanup, copy coalescing, and a **register allocator** (liveness, live
    intervals, linear scan; scratch registers for values that don't live across calls).
  - `src/x64.strata`: IR -> x86-64 assembly (immediates, addresses folded into memory
    operands, compare-and-branch fusion, stack probes for big frames).
  - `lib/srt.c`: the runtime entry points native code calls (printing, arenas,
    strings, arrays, files, matrices). Compiled with the C toolchain for now, like the
    assembler and linker; replacing those is next.
  - Measured against gcc -O2 (best of 5): vector simulation 91 vs 83 ms, a sieve 201 vs
    156 ms, recursive fib 166 vs 78 ms. A 20k-line program builds and runs in 0.97 s
    (3.6 s through C and gcc).
- **`--backend native|c|auto`** on `run` / `build`. `auto` (the default) builds natively
  when it can, else with C: today the native backend needs x86-64 Windows, an exe (not
  a dll), and no imported C headers (it can't read them yet).
- `stratac asm <target>` prints the generated assembly; `stratac ir <target>` the IR
  (`--release`: optimized).
- `PlatformArch()` in `lib/crossplatform.h` ("x86_64", "arm64").
- **Importing `<crossplatform.h>` links its OS library automatically**: user32 on
  Windows, Cocoa on macOS, X11 on Linux (not when the project defines
  `STRATA_CROSSPLATFORM_NO_WINDOW`). `examples/crossplatform.strata` no longer needs
  `link "user32"`, so it builds as a single file on every OS.
- Tests (63): `examples/abi.strata` (struct passing, 7-argument calls, narrow and
  unsigned arithmetic, shifts, floats, short-circuiting, pointers), the `pure` project
  (native debug builds of a multi-module program), every run golden forced through
  each backend, and `stratac asm`.

### Changed
- Builds are native by default where possible (see `--backend`); single files and
  `--release` builds are optimized.
- C backend: an integer literal shifted left is widened to 64 bits first (`1 << 40` was
  a 32-bit C overflow; Strata's `int` is 64-bit).

### Removed
- `archive/` (the original D-- compiler and the D-- -> Strata translator; still in git
  history).

## [1.6.0] - 2026-10-06
### Added
- **`stratac` itself is cross-platform: Windows, macOS and Linux.** Everything that
  differs between them goes through `lib/crossplatform.h` (see below) from
  `src/strata_host.h`; no `cmd.exe`, no `system()`. Programs are `foo.exe` on Windows and
  `foo` elsewhere; shared libraries are `.dll` / `.dylib` / `.so` (macOS: an `@rpath`
  install name, Linux: a soname; the `.dll.a` import library is Windows-only). The C
  compiler is `gcc` on Windows, `cc` elsewhere, or `$STRATA_CC`. `host_os()` now reports
  the real platform, so a project's `[windows]` / `[linux]` / `[macos]` section applies
  where it should. `stratac` finds its `lib/` from its own path (also when started from
  PATH or through a symlink), and `libstrata` from the library's path.
- **`lib/crossplatform.h`: System, Files and Process sections** beside Window:
  `PlatformName`, `PlatformCpuCount`, `PlatformExecutablePath`, `PlatformModulePath`;
  `PlatformPathExists`, `PlatformIsDirectory`, `PlatformMakeDirectories` (mkdir -p);
  `PlatformStartProcess` / `PlatformWaitProcess` / `PlatformRunProcess` (no shell;
  arguments arrive exactly as given, quoted for the Windows C runtime). New option
  `STRATA_CROSSPLATFORM_STATIC` keeps every function private to the including file.
  `<windows.h>` is now included only for the Window section.
- **Bootstrapping on macOS / Linux: the C seed** (`compiler/seed/`): a `stratac`
  compiled to portable C plus the headers it was generated against. `build.sh` compiles
  it with `cc` as stage0, then does the usual stage1 → stage2 fixpoint. Make or refresh
  it with `build.ps1 -WriteSeed` or `build.sh --write-seed`.
- POSIX scripts beside the PowerShell ones: `build.sh`, `tests/run.sh` (the same
  checks as `run.ps1`), `install.sh` (`~/.local/share/strata`, linked into
  `~/.local/bin`), `package.sh` (a `.tar.gz`).
- CI (`.github/workflows/ci.yml`): Windows bootstraps from the pinned release and makes
  the seed; macOS and Linux bootstrap from it and run `tests/run.sh`.
- `stratac new` writes a `[macos]` section too.
### Changed
- Single-file builds run the C compiler directly with one argument per flag (no shell
  quoting), so build fingerprints change once: every cached project rebuilds once.
- The embedding test host (`tests/embed/host_api.c`) measures memory on macOS and Linux
  too.
- `if` / `while` conditions are emitted without doubled parentheses (`if (n == 5)`, not
  `if ((n == 5))`), which clang warned about in every program (`-Wparentheses-equality`).
- Each imported C header is `#include`d once, however many modules import it (the
  compiler's own C had `#include "strata_host.h"` seven times).

## [1.5.0] - 2026-09-26
### Added
- **`break` and `continue`** in `while`, `for x in a..b` and `for x in array` loops.
  `break` inside a `switch` leaves the loop (Strata's switch has no fall-through), and
  leaving a `region` early frees it. Outside a loop they are an error.
- **Incremental, parallel project builds.** A project is compiled as several C files:
  a shared header with the types, and modules grouped into chunks (about two per
  core). Each C file declares only the exports of the modules it imports. So editing a
  function body recompiles one chunk, and changing an export recompiles only the
  modules that import it. gcc runs in parallel, started directly (no `cmd.exe`).
  `split = false` in `[build]` opts out.

  81k-line project: full debug build 16.8 -> 4.1 s, release 27.8 -> 4.9 s, rebuild
  after editing one function 12.9 -> 1.0 s.
- **A nesting limit:** code nested more than 1,000 levels deep (parentheses, calls,
  blocks, unary operators) is a clear parse error instead of a stack overflow, which
  also keeps engines that embed the compiler safe on a 1 MB thread stack.
- Tests (58): a multi-module split project, an incremental-rebuild check, a
  break/continue example with its error cases, and limit checks (1,001-deep nesting
  is an error; a 100,000-term expression compiles in well under 3 s).
### Fixed
- **`return` inside a `region` leaked the region.** It now evaluates its value, frees
  every open region, then returns.
- **Four more quadratic code-generation paths, which crashed on big inputs:**
  - a 1 MB string literal took 21 GB and crashed; it now takes 0.05 s and 12 MB
  - a 100,000-item array literal took 24 GB and crashed; a 1,000,000-item one now
    takes 1.4 s
  - a function with 10,000 parameters took 7 GB; it now takes 11 MB
  - code nested 5,000 blocks deep took 22 GB
- **Long operator chains** (`a + b + c + ...`) no longer recurse or re-copy: 8,000
  terms went from 1.2 GB to 4 MB, and a 1,000,000-term expression compiles in 0.8 s.
- Runtime state (arenas, remembered string lengths, `args()`) is shared correctly
  across a split program's C files (`lib/sstate.h`). Single-header C libraries like
  `crossplatform.h` are implemented once, in the main module's file.
### Performance
- Memory (81k-line project): check 109 -> 92 MB, emit 152 -> 135 MB. Primitive
  types are shared, identifiers are interned per file, and the AST node structs are
  packed.

## [1.4.0] - 2026-09-26
### Performance
The compiler is **25–540× faster** and uses **up to 40% less memory** than 1.3.0
(check/emit, measured on an 81k-line 200-module project, a 20k-line single file, and the
compiler itself):

| | 1.3.0 | 1.4.0 |
|---|---|---|
| 20k-line file, check | 16.25 s | **0.03 s** |
| 81k-line project, check | 3.9 s, 151 MB | **0.15 s, 109 MB** |
| 81k-line project, emit | 2.5 s, 241 MB | **0.27 s, 152 MB** |
| the compiler itself, check | 0.27 s | **0.01 s** |

- **String lengths are remembered.** Strata strings are C strings, so `.len`, `substr`
  and `+` scanned the whole string every time; the lexer did that per token, which made
  it quadratic in file size. The runtime now remembers the length of every long string
  it creates (a pointer -> length table; strings are immutable and only freed on reset).
  This speeds up every Strata program, not just the compiler.
- **Hashed name lookups** in the checker: every lookup and the module name rules used to
  scan all declarations (hundreds of millions of comparisons at 10k functions).
- **One-pass output join** in codegen (the pairwise join copied the output ~20 times).
- **Less memory:** each module's tokens are freed once it's parsed; fixed tokens (`+`,
  `var`, ...) share one string instead of a copy each; expressions of the same named type
  share one result-type node.
### Added
- A performance guard in the tests: a generated 20k-line file must check in under 3 s
  (1.3.0 takes 17 s on it). 51 checks.

## [1.3.0] - 2026-09-26
### Added
- **The compiler as a library, for engines.** `libstrata.dll` exports a public C API
  (`compiler/api/strata.h`):
  - `strata_check` / `strata_check_source` (in-memory source, e.g. an editor buffer)
  - `strata_emit` / `strata_emit_source` (to C)
  - `strata_build` / `strata_output_path` (exe or dll, via gcc, cached for projects)
  - `strata_diagnostics` (messages are captured, not printed)
  - `strata_set_libdir` (the runtime lib/ folder is found next to the dll by default)
  - `strata_reset` (frees all compiler memory, so an engine can recompile indefinitely)

  The API is written in Strata (`src/libstrata.strata`) and built by
  `compiler/api/strata.toml`. Wrappers: `strata.hpp` (C++) and `Strata.cs` (C#,
  P/Invoke: Unity, Godot C#, ...).
- **Strata dlls are proper libraries:** a dll exports exactly its entry module's
  `export`ed functions, and the build writes a generated C header (`<name>.h`) and an
  import library (`<name>.dll.a`) next to it.
- **Embedding license:** `LICENSE-EMBEDDING.md` (the GNU Classpath exception applied to
  Strata) lets any engine embed libstrata, whatever its license.
- The install and release zip add `include/` (strata.h, strata.hpp, Strata.cs) and
  `libstrata.dll.a`.
- Tests (50): host programs that embed the compiler from C, C++ and C#, and a C
  program calling a Strata-built dll through its generated header. One test runs 300
  compile + reset cycles and checks that memory stays flat.
### Changed
- Compiler messages go through one sink (`src/strata_host.h`): printed by the CLI,
  captured by the library. Dynamic arrays can now all be freed at once (hosts only).

## [1.2.0] - 2026-09-26
### Added
- **Build system: projects.** A `strata.toml` project file (a small TOML subset) sets
  the name, entry file and output (`exe` or **`dll`**), plus `[build]` defines,
  include/library folders, extra **C source files** and libraries. `[windows]` /
  `[linux]` / `[macos]` sections set per-platform libraries (and macOS frameworks),
  which `link` in source can't express. Unknown keys and sections are errors.
- **Build cache.** A project build fingerprints everything that affects the binary
  (generated C, the gcc command, extra C sources, the compiler version) and skips gcc
  when nothing changed: `up to date: build/game.exe`. `--force` rebuilds.
- **Commands:** `stratac new <name>` scaffolds a project. `stratac build` / `run` /
  `check` / `emit` take a project folder, a `strata.toml`, a `.strata` file, or nothing
  (the project in the current folder). `--release` builds `-O2` (default `-O0 -g`);
  `--` passes the remaining arguments to the program. Single `.strata` files build
  exactly as before.
- **DLL output:** `output = "dll"` builds a shared library with no `main`. Exported
  functions are its entry points; an entry file with top-level code is an error.
- Tests: `tests/projects/` (a native-C project, a dll, a bad project file), each also
  checking that a second build is cached (46 checks).
### Fixed
- **Code generation used memory quadratic in program size.** A 12k-line program took
  23 GB and 11 s to generate, and 16k lines crashed. Output is now collected as pieces
  and joined once: 12k lines take 0.19 s and 38 MB, and 81k lines take 2.5 s and 241 MB.
- The checker relied on C's `break` leaking through as an unknown name; rewritten
  without it (Strata has no `break`/`continue` yet).

### Changed
- **The compiler's Strata source moved to `compiler/src/`** (from `compiler/selfhost/`).
  The D-- original and the D--→Strata translator are retired to
  `archive/dminusminus-seed/`.
- **The build no longer needs D--.** `build.ps1` bootstraps from a pinned `stratac`
  release (`compiler/bootstrap.txt`, now 1.1.0), downloaded once and cached. It falls
  back to the installed `stratac` when offline; `-Bootstrap <exe>` overrides. The
  fixpoint check (stage1 and stage2 emit identical C) still gates every build.
- Tests: the token-parity check against the D-- seed is gone with the seed (43 checks).

## [1.1.0] - 2026-09-26
### Added
- **`lib/crossplatform.h`**: a single-header platform layer (Windows / macOS / Linux),
  starting with a Window section (create, poll events, title, size, close). Strata
  programs just `import <crossplatform.h>`; C/C++ define `STRATA_CROSSPLATFORM` in one
  file. Each section can be left out (`STRATA_CROSSPLATFORM_NO_WINDOW`). Example:
  `examples/crossplatform.strata`.
- **A real module system.** Every file is a module and its top-level declarations are
  **private unless `export`ed**:
  - `import gfx.Renderer` loads `gfx/Renderer.strata` from the project root (the main
    file's folder) and makes its exports visible to that file. Imports are not
    transitive.
  - `export import X` re-exports a module; `core` is now such an umbrella.
  - Private names can repeat across modules; colliding ones get module-prefixed C names
    (`mods_shapes__helper`). Exported names must be unique.
  - New errors: using a private declaration, using something from a module you didn't
    import, clashing with an import, duplicate exports, a missing module, top-level
    code in a module. Each error names the file and says how to fix it.
  - Modules are now parsed file by file (new core module `modules`), so every error
    points at the right file and line. The line-map workaround (`srcmap`) is gone.
  - The compiler's own source now uses the system: 135 exports and explicit imports.
- `stratac ast` shows `import` / `export` (`Import module X`, `export Func ...`).
- Tests: `emit` goldens pin the generated C for every example. They replace the
  `ast`/`check`/`emit` parity checks against the D-- seed (token parity stays).
- Generated C now starts with `#define STRATA_PROGRAM 1`. A Strata program is always one
  C file, so single-header C libraries can compile their implementation automatically
  when they see it.

## [1.0.0] - 2026-09-24
**Strata is self-hosted:** the compiler is written in Strata and compiles itself.
### Added
- The whole compiler is ported to Strata (`compiler/selfhost/`): token, lexer, srcmap,
  ast, parser, checker, codegen, core, dump, the `stratac` driver and the `console`.
  `tools/dmm2strata.py` translated every module with **no hand edits**.
- **Bootstrap build** (`build.ps1`): `dec` builds the frozen D-- seed (stage0), stage0
  builds the Strata compiler (stage1), stage1 builds it again (stage2). The build fails
  unless stage1 and stage2 emit byte-identical C for the compiler (the fixpoint). stage2
  ships as `bin/stratac.exe`; `console.exe` and `libstrata.dll` are built from Strata too.
- Tests: `run.ps1` runs the bootstrap, all goldens against the self-hosted compiler, and
  a **parity** check. On 40 files, every stage (`tokens`, `ast`, `check`, `emit`) is
  byte-identical to the D-- seed.
- **Editor support** (`editors/`): syntax highlighting for **VS Code** and **Visual Studio**
  from one TextMate grammar, generated by `editors/build_grammar.py` from word lists that
  mirror the lexer and checker. Covers keywords, primitive and user types, `cast<T>` /
  `sizeof(T)`, module and C-header imports, `link`, strings and char escapes, numbers,
  nested block comments, built-ins and function names. The VS Code extension also sets up
  comment toggling, bracket matching and indentation. One-command installers for each
  editor.
### Changed
- **String and char literal tokens keep their text as written** (`"a\nb"` stays
  backslash-n), with escapes still validated by the lexer. Every Strata escape is a C
  escape, so codegen emits it directly. The compiler never has to hold a NUL byte in a
  (NUL-terminated) string, which is what made self-hosting byte-exact. `stratac tokens`
  and `ast` now show escapes rather than raw control characters.
### Fixed
- `dmm2strata.py`: no longer rewrites code inside string/char literals (it had turned
  a C `for (...)` that codegen emits into Strata syntax), handles `for (...; i <= n; ...)`,
  and translates D--'s `int main(str[] args)` into a function called from top-level code.

## [0.17.0] - 2026-09-22
### Added
- **Self-hosting: the parser is ported.** `selfhost/` now also has `srcmap`, `ast`, `parser`
  and the full `dump` (token + AST printer), and the Strata-written driver has an `ast`
  command. The self-hosting test checks both `tokens` and `ast` output, byte-for-byte,
  over 36 files. Still no hand edits in the ported modules.
### Changed
- **Newlines inside `(` and `[` no longer end a statement** (Python's rule), so a condition
  or argument list can wrap after any token, e.g. a line ending in an identifier.
### Fixed
- `dmm2strata.py` converts `new T{...}` literals that span lines or nest, by matching
  braces over the whole text rather than line by line.

## [0.16.0] - 2026-09-22
### Added
- **Self-hosting begins:** `compiler/selfhost/` holds the compiler being ported to Strata.
  The lexer (`token.strata`, `lexer.strata`), the token printer (`dump.strata`) and a
  `tokens`-only driver (`stratac.strata`) are ported. They were converted by
  `tools/dmm2strata.py` with no hand edits. `tests/run.ps1` builds the Strata-written
  driver and requires its output to be byte-identical to the D-- build over every example
  and every compiler source file (33 files).
- **Built-ins** (the set the compiler source uses, same signatures as D--):
  `substr(s, start, len)`, `int_to_str(n)`, `read_file(path)`, `write_file(path, data)`,
  `cstr(s)` (identity; a `string` already is a C string), and `args()` (the command line
  as a `string[dynamic]`). New runtime header `lib/sio.h`.
- **`;` is an optional statement separator** (as in Go), so `{ a; b }` fits on one line.
- **Parse errors are located:** `file:line:col: parse error: expected ')', got NEWLINE`
  (previously just "parse error in <file>").
### Fixed
- Errors in imported modules report the module's own file and line (a line map is kept
  while modules are pasted together); previously lines were offsets into the combined text.
- An array literal takes its element type from the array type it initializes or is
  assigned to, returned as or passed as. `Token[dynamic] ts = []` previously allocated
  8-byte elements.
- `'` and NUL are escaped in emitted C char/string literals (`'\''` produced invalid C).
- `stratac run prog.strata` (no directory in the path) now finds the built exe.
- `dmm2strata.py`: converts `#include` lines that carry a trailing comment, maps D--'s
  growable `T[]` to `T[dynamic]`, writes UTF-8, and no longer flags lines it converted.

## [0.15.0] - 2026-09-22
### Added
- **`cast<T>(x)`** — explicit conversion: between scalars (`int`/sized ints/`float`/
  `char`/`bool`/enums) and involving pointers (pointer↔pointer, pointer↔int). Other
  casts (e.g. `cast<vec3>(5)`) are a checker error. Lowers to a C cast.
- **`sizeof(T)`** — the size of any type in bytes, as an `int`.
- These were the last two features `tools/dmm2strata.py` flagged as missing for
  self-hosting. Example: `examples/casts.strata`.
### Fixed
- Sized numeric types (`i8`..`u64`, `uint`, `f32`, `f64`) now map to their C types
  (`int32_t`, `uint8_t`, `double`, ...) instead of leaking their Strata names into the C,
  and `var` inference keeps the sized type rather than collapsing it to `int`/`float`.

## [0.14.0] - 2026-09-22
### Added
- **`alloc(value)`** — boxes any value in a global heap and returns a pointer to it
  (allocate-and-initialize; `world.new(T)` remains for zeroed region allocation).
- **`null`** — the null pointer, assignable to any pointer type.
- Together these enable heap-allocated node graphs (e.g. a compiler's AST) — the last
  core piece before self-hosting. Example: `examples/list.strata` (a linked list).

## [0.13.0] - 2026-09-22
### Added
- **Modules:** `import Name` pulls in `Name.strata`; dotted paths go through folders
  (`import gfx.Renderer` → `gfx/Renderer.strata`). Deduplicated and recursive. Distinct
  from the quoted/angled `import "x.h"` / `import <x.h>` C-header form.
- **`export`** marks a declaration public (intent; full private-symbol enforcement is
  planned). This is the multi-file support needed to eventually self-host the compiler.

## [0.12.0] - 2026-09-22
### Added
- **Prelude** (always in scope): `min`, `max`, `clamp`, `lerp`, and the constant `PI`.
  (`sqrt`/`sin`/`cos` are available via `import <math.h>`.)

## [0.11.0] - 2026-09-22
### Added
- **Enums** now compile to C enums (`enum State { Idle, Walk, Jump }`).
- **`switch`** statements: `switch x { case A: ... case B, C: ... default: ... }`, with
  **no fall-through** (each case breaks) and multi-value cases. Works on ints and enums.
  This is the AST-dispatch pattern needed to eventually self-host the compiler in Strata.

## [0.10.0] - 2026-09-22
### Added
- **Dynamic arrays** (`T[dynamic]`): array literals `[a, b, c]`, `.push(v)`, `.len`,
  indexing (including as an lvalue: `xs[i].field = ...`), and `for x in xs` iteration.
- Works for struct elements, so **entity lists** work (`examples/balls.strata` — 60
  bouncing balls, a `Ball[dynamic]` with vec2 physics + raylib).
- Type-erased `Array` runtime (`compiler/lib/sarr.h`).

## [0.9.0] - 2026-09-22
### Added
- **C library linking:** the `link "name"` directive adds `-lname` to the build.
- Unknown *names* resolve as external C symbols once a header is imported (e.g. raylib
  constants like `RAYWHITE`).
- `examples/window.strata` — a raylib window written in Strata, built to a single native
  binary. (`examples/sprite.strata`, an arrow-key-driven sprite, followed.)

## [0.8.0] - 2026-09-21
### Added
- **Strings:** `string` (a C `const char*`) with concatenation (`+`), `.len`, and `==`/`!=`
  (`compiler/lib/sstr.h`).
- **C interop:** `import "h.h"` / `import <h.h>` emits `#include` and enables calling
  external C functions directly (verified against libc `puts`/`abs`).

## [0.7.0] - 2026-09-21
### Added
- **Matrices and quaternions:** `mat4` (mul, transform, `translate`/`scale`/`rotate`/
  `perspective`/`look_at`), `quat` (mul, axis-angle, rotate, `to_mat4`, normalize).
- **Vector swizzles:** `v.xy`, chained (`a.zw.y`).
### Project
- SPDX + copyright headers on all source; CLA, commercial-license offer, contributing guide.

## [0.6.0] - 2026-09-21
### Added
- **First-class vectors:** `vec2/3/4` with constructors, component-wise `+`/`-`/`*`, scalar
  scale, `.x/.y/.z/.w`, and `dot`/`cross`/`length`/`normalize` (`compiler/lib/smath.h`).
- The flagship `examples/hello.strata` (struct + vec3 + arena, no GC) runs end-to-end.

## Pre-release (milestone 1) - 2026-09-20 to 2026-09-21
Built before the first tagged release:
- Lexer (significant newlines, `..` ranges, types-first tokens).
- Parser (recursive descent; structs, functions, `var`/typed decls, paren-free control flow).
- Type checker (name resolution, type checking, `var` inference).
- C codegen; arena/region memory (`compiler/lib/arena.h`).
- The compiler (`stratac`), written in D--, split into a reusable core + front-ends
  (`stratac` CLI, `console`, `libstrata.dll`), with a byte-for-byte golden test suite.

[Unreleased]: https://github.com/UseStrata/Strata/compare/v0.13.0...HEAD
[0.13.0]: https://github.com/UseStrata/Strata/releases/tag/v0.13.0
[0.12.0]: https://github.com/UseStrata/Strata/releases/tag/v0.12.0
[0.11.0]: https://github.com/UseStrata/Strata/releases/tag/v0.11.0
[0.10.0]: https://github.com/UseStrata/Strata/releases/tag/v0.10.0
[0.9.0]: https://github.com/UseStrata/Strata/releases/tag/v0.9.0
[0.8.0]: https://github.com/UseStrata/Strata/releases/tag/v0.8.0
[0.7.0]: https://github.com/UseStrata/Strata/releases/tag/v0.7.0
[0.6.0]: https://github.com/UseStrata/Strata/releases/tag/v0.6.0
