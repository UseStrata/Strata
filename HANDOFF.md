# Strata — Handoff

> The pick-up-cold guide: what Strata is, how the compiler works, how to build / test /
> release it, what exists, what's limited, and what's next. Read this first; then
> [`compiler/ARCHITECTURE.md`](compiler/ARCHITECTURE.md) (compiler internals),
> [`CHANGELOG.md`](CHANGELOG.md) (per-version detail) and
> [`website/design/DESIGN.md`](website/design/DESIGN.md) (language design).

**Current:** stratac **2.6.0** (native everywhere: Windows x86-64, Linux x86-64, macOS ARM64; function pointers), released 2026-10-11
· on `main` (unreleased, → 2.7.0): **the C backend is gone** — Strata is C-free (§0)
· tests **57/57** (Windows), Linux / macOS in CI · repo **https://github.com/UseStrata/Strata**
· installed on this machine at `%LOCALAPPDATA%\Programs\strata` (on the user PATH; 2.6.0)
· releases ship windows-x64.zip, linux-x64.tar.gz and macos-arm64.tar.gz (the last two cross-compiled by
  package.ps1; CI checks those compilers equal the ones Linux / macOS build natively)

**The direction (user, 2026-10-08):** Strata grows **independent** — step by step, until it
relies on nothing but the OS and what a game engine provides. 2.0 was step one (its own
x86-64 code generator); on `main`, after 2.6.0, the C backend and the C seed are deleted:
Strata compiles, assembles and links everything itself, on every OS. See §12.

---

## 0. Start here (handoff from the 2026-10-09 chat)

**The user's latest instruction (2026-10-09), verbatim:** *"do those all in order but also
remove the C compilation process just make it assembly we don't need C"* — "those" = the
plan below. Asked when C should go, the user chose **at the end**: (1) ~~release 2.4.0~~,
(2) stack-slot sharing in the optimizer, (3) native dlls (libstrata without gcc), (4) native
ARM64 Mach-O + x86-64 ELF backends (macOS / Linux; testable only through CI), (5) **then
delete the C backend** (codegen, `--backend c`, `emit`, `import <x.h>`, the C seed,
`strata_host.h`, `lib/*.h`). Nothing may break along the way. **All five steps are done**
(2026-10-11; step 5 on `main` after the 2.6.0 release, which pins every OS's bootstrap).

The instruction before it: *"do whatevers best but just try to move away
from c so we can clean up a lot of stuff"* — then: put that in this file and move to a new
chat. So: **keep moving Strata off C, and clean up what that frees** (fewer C files, fewer
gcc/C code paths). Use judgment on the order; prefer steps that remove a dependency. The
user has repeatedly said "do the next best thing" / "release both": they want progress
plus releases, and approve releases when asked.

**State right now**
- **2.2.0** released 2026-10-09: the native runtime rewritten in Strata (`lib/srt.strata`,
  built by `stratac object`; `lib/srt.c` deleted), the `foreign` block and `global`
  variables (both user-chosen designs, DESIGN.md §3/§8), exact float printing, 68 tests.
- Releases: follow §3's steps. Ask the user before pushing / publishing.
- **2.3.0** released 2026-10-09: `struct`s and `const`ants in `foreign` blocks; the raylib
  examples import `examples/raylib.strata` and build natively; Strata's linker links
  `link "x"` / `libs` against the libraries' DLLs (raylib builds with no gcc). 71 tests.
- **2.4.0** released 2026-10-09: **the compiler compiles itself natively.** `build.ps1`
  bootstraps stage0 (2.3.0) → stage1 → stage2 → stage3, all with the native backend, no
  gcc; stage2 == stage3 byte for byte. Compiler modules `import host` (`src/host.strata`,
  a foreign block): `strata_host.h` serves the C build (macOS / Linux, the seed), the
  `strata_*` functions at the end of `lib/srt.strata` the native one. Evaluation order is
  now left to right on both backends (DESIGN.md §8b). 72 tests.
- **2.5.0** released 2026-10-09: native dlls (libstrata too: build.ps1 needs no gcc at all),
  relocatable, with import libraries Strata writes (`.dll.a`, `.lib`); native stack frames
  63% smaller (spilled vregs share slots). 73 tests.
- **On `main` (unreleased): the backend's two-axis layout** (the user's design): one
  assembler (`asm.strata`) + one file per CPU (`arch/x64.strata`), one linker entry
  (`linker.strata`) + one file per OS (`os/windows.strata`); outputs byte-identical to
  2.5.0. Grow them only when needed (the ABI rules stay in `lower` until a second
  convention arrives).
- **On `main` (unreleased): native Linux x86-64** (step 2 of the agreed order): `--target
  linux-x64` (`src/target.strata`), `src/os/linux.strata` (ELF objects + a static ELF
  linker, `_start` / `srt_syscall` stubs), `lib/srt/linux.strata` (the runtime on system
  calls; `lib/srt.strata` `when`-imports `srt/windows` or `srt/linux`). Strata's own
  calls are System V on Linux; programs that call shared libraries link dynamically
  (libc auto-needed; 8-byte `jmp *slot` stubs, GLOB_DAT, BIND_NOW), and `output = "dll"`
  is a native `.so` (`elf_link_so`: base 0, R_X86_64_RELATIVE for every 64-bit address,
  DT_SONAME, DT_FINI_ARRAY -> srt_os_flush; no srt_os_init, so getenv is null there).
  CI's Linux job runs every run golden natively. On Linux, `auto` uses C only for projects
  with C sources; the compiler itself still builds through C there (build.sh `--backend c`).
- **2.6.0** released 2026-10-11: everything below marked "on main" up to here - native
  Linux x86-64 and macOS ARM64, CrossPlatform, `when`, link names, function pointers - and
  the first macOS / Linux release archives. The last release with the C backend.
- **On `main` (released in 2.6.0): function pointers** (the user needs them for an engine
  project): `TypeKind.TyFunc` (TypeNode `elem` = result, `args` / `next` = the parameter
  chain), parsed by `parse_fn_type` (`fn(` in a type position; `(fn ...)` groups); the
  checker's `TcFunc` keeps the node (`Type.sig`) and compares signatures as text
  (`node_str`); a function name as a value -> `ty_fn(func_node)`; calls through variables,
  globals, struct fields (`ck_fn_field`) and any expression go to `ck_call_ind`, which
  sets the call's `e.type` = the signature - the backends' marker for an indirect call.
  lower: `call_indirect` (callee evaluated first, a synthetic Decl from the signature,
  `l.ind` = the target vreg, taken by the convention's call builder before it lowers the
  arguments) -> `OCall` with `a` >= 0; x64 `call *%r11` (FF /2), ARM64 `blr x16`, both
  loaded last; Mach-O / ELF / PE resolve a foreign function's address to its stub.
  codegen: `fn_typedef` (`strata_fn<N>`, slot after the struct forward declarations;
  split builds fill the header slot after the units). Tested by run/callbacks (both
  backends, qsort calling back) and embed/strata-dll (a C host calling through a
  Strata-filled `MathOps` table and passing a C callback), on all three OSes.
- **On `main` (unreleased): native macOS ARM64** (step 4 of the agreed order):
  `src/arch/arm64.strata` (one file: the code generator - IR -> LLVM-syntax ARM64 text,
  then assembled; x19-x28 / d8-d15 allocated, x13-x15 / d18-d23 for values not living
  across calls, x9-x12 / d16-d17 scratch, x16 / x17 address temps, locals addressed from
  sp - and the encoder, byte-identical to clang: run.ps1's backend/arm64-assembler
  checks every example when LLVM clang is installed), the Apple ARM64 convention in
  `lower.strata` (`aapcs()`; `aapcs_spec`: 64 + 8 * f64 + count for an HFA, 1-2 integer
  registers, 0 by address; arg_bytes -2 = x8, 100000 + size = an HFA copied to the stack),
  `src/os/macos.strata` (Mach-O objects with `_` names; the linker: __PAGEZERO / __TEXT /
  __DATA / __LINKEDIT on 16 KB pages, 12-byte stubs + __got bound by dyld bind opcodes -
  ordinal 1 with only libSystem, flat lookup with more - rebase opcodes for data
  pointers, LC_MAIN -> a start stub doing atexit(srt_os_flush), main, exit; dylibs: id
  `@rpath/<file>`, export trie, a __mod_init_func doing the atexit; an ad-hoc,
  linker-signed CodeDirectory), `lib/srt/macos.strata` (libSystem; stdout buffered
  here). macOS CI builds lib/srt-macos-arm64.o and runs every golden natively, and `auto`
  is native there now. Cross-check locally with LLVM (C:\Program Files\LLVM\bin:
  llvm-objdump --macho, ld64.lld against a hand-written libSystem .tbd).
- **On `main` (unreleased): the CrossPlatform library in Strata** (user's idea and
  naming): `import CrossPlatform` → `lib/CrossPlatform.strata` (the API, same on every OS)
  + `lib/CrossPlatform/windows.strata` (user32 / kernel32 / msvcrt), which the main file
  imports with `when target_os == "windows" { import CrossPlatform.windows }` (the user's
  `when` design, DESIGN.md §8c), + `lib/CrossPlatform/linux.strata` (X11 via `link
  "X11"`, libc: sysconf, readlink, stat, mkdir, fork + execvp with a CLOEXEC pipe so a
  program that can't run gives -1; the runtime's `fflush` flushes srt's stdout buffer).
  Window, system, files, programs; native on both (Linux golden: tests/run/
  platform.expected.linux; run.sh opens/closes the window on Xvfb with xdotool). Programs
  importing CrossPlatform on Linux need libX11.so.6 at run time (no dead-function
  removal yet: every os_* function is compiled in). Imports fall back to Strata's `lib/`.
  + `lib/CrossPlatform/macos.strata` (Cocoa through libobjc: `objc_getClass`,
  `sel_registerName`, one link-named foreign function per objc_msgSend signature -
  NSRect / NSSize are HFAs; setReleasedWhenClosed:NO + isVisible polled for the close
  button; an autorelease pool per poll; NSDefaultRunLoopMode as the string
  "kCFRunLoopDefaultMode"; posix_spawnp for programs). run.sh opens / runs / closes it on
  CI's Mac (skipped where there's no window server).
  Next: port the compiler's own OS code onto it. No window drawing yet (only the window
  itself).

**C is gone (on `main`, after 2.6.0).** Deleted: `src/codegen.strata`, `stratac emit`,
`--backend c` (`native` / `auto` still accepted: every build is native), split C builds,
`import <x.h>` (an error saying to use a foreign block), the project keys `c_sources` /
`include_dirs` / `defines` (errors; `split` accepted and ignored; macOS `frameworks` are
libs), the C runtime headers `lib/*.h` (incl. `crossplatform.h`), `src/strata_host.h`,
`compiler/seed/`, `strata_emit(_source)` in the embedding API. The dll C header generator
moved to `src/cheader.strata` (it defines vec / mat4 / quat / Array itself now). macOS /
Linux bootstrap from 2.6.0's release archives (build.sh), like Windows. What C remains:
the tests compile their C / C++ host programs with gcc / cc (they test the C API), and
run.ps1 compares Strata's x86-64 assembler with GNU as when objdump is there. Optional
polish: the Windows runtime calls msvcrt.dll (could go to kernel32), and C header import
(reading declarations into foreign blocks) is the main interop item left.

**Suggested order:** (a) ~~release 2.2.0~~ done; (b) ~~`struct` (and constant) declarations in
`foreign` blocks + native raylib examples~~ done; (c) ~~`pelink` resolving `link "x"` DLLs itself~~ done;
(d) ~~the compiler compiled natively~~ done on Windows (2.4.0). Then: (e) ~~stack-slot
sharing~~ done for vregs (2.5.0: dead vregs get no slot, spilled vregs share slots;
frames -63%); IR slots (struct temporaries / locals) still don't share - that needs escape
+ loop-lifetime analysis, low priority now; (f) ~~native dlls~~ done (2.5.0: libstrata
and `output = "dll"` projects build natively, with import libraries); (g) ~~ARM64 / ELF /
Mach-O targets~~ done (on main); (h) reading C headers into foreign blocks. Static `.a` archives in `pelink` were looked at and skipped: MSYS2's libraylib.a
needs mingw's own static runtime (`__mingw_printf`, `__stack_chk_*`), i.e. the toolchain.

**Gotchas learned this session** (also in §13): the shell mangles backslashes in heredocs
and inline Python (`\n` → newline, `\0` → NUL, `\t` → tab) — write edit scripts with the
editor tool to a scratch file and run `python -I script.py`; stage0 (1.1.0) emits `1 << k`
as a 32-bit C shift (use a `u64` variable); C keywords (`asm`, `unsigned`) and Strata
keywords (`var`) can't be identifiers in the compiler's source; a freshly built `.exe` is
slow on first launch (Windows scans it) — benchmark best-of-5; msvcrt's float→decimal
conversions are not correctly rounded (the runtime does its own).

---

## 1. What Strata is

A statically-typed, **compiled** language **for games and real-time software**. It compiles
to **native code itself** — x86-64 Windows, x86-64 Linux, ARM64 macOS (`lower → opt →
arch/<cpu> → asm → linker`) — with no C compiler anywhere. Pitch: *"safer than C, simpler than
Rust: the control C gives games, without the footguns or the borrow-checker fight."*

- **Arena / region memory**: no GC, no manual `free`. Everything in a region dies together.
- **First-class math types**: `vec2/3/4`, `mat4`, `quat`, swizzles, operators.
- **C interop**: `foreign` blocks (functions, structs, constants, link names, callbacks), `link "lib"`.
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
│  ├─ build.sh           the same on macOS / Linux (stratac, console, libstrata.dylib/.so)
│  ├─ bootstrap.txt      the release every OS's build bootstraps from (2.6.0)
│  ├─ install.ps1/.sh    install (Windows: %LOCALAPPDATA%\Programs\strata + PATH; else ~/.local)
│  ├─ package.ps1/.sh    release zip / tar.gz into dist/
│  ├─ src/               THE COMPILER, in Strata (§4)
│  ├─ lib/               the runtime programs link (§7: srt.strata + srt/<os>.strata) + CrossPlatform
│  ├─ api/               libstrata's project file + strata.h / strata.hpp / Strata.cs (§6)
│  ├─ examples/          sample programs, also the golden-test inputs (§8)
│  ├─ tests/             run.ps1 / run.sh + goldens + test projects + embedding hosts (§9)
│  └─ bin/ build/ dist/  build output, bootstrap compilers, release zips (gitignored)
├─ .github/workflows/    ci.yml: Windows, then macOS + Linux (each bootstraps from the pinned release)
├─ editors/              VS Code + Visual Studio syntax highlighting (generated grammar)
└─ website/design/       DESIGN.md: the language design
```

---

## 3. Build, test, run, release

**Prerequisites (set up on this machine):** none to build Strata itself. For the tests: gcc
via MSYS2 (`C:\msys64\mingw64\bin`, on PATH) compiles the embedding hosts (C / C++) and
provides objdump / as for the GNU-as comparison; raylib via MSYS2 for the graphical
examples; LLVM (`C:\Program Files\LLVM\bin`: clang, llvm-objdump, ld64.lld) for the ARM64
assembler check and Mach-O inspection; .NET SDK (optional) for the C# host.

```
powershell -ExecutionPolicy Bypass -File compiler\build.ps1        # bootstrap + build
powershell -ExecutionPolicy Bypass -File compiler\tests\run.ps1    # build + all checks
powershell -ExecutionPolicy Bypass -File compiler\install.ps1      # rebuild + install globally
```

**The bootstrap** (`build.ps1` / `build.sh`, **no C compiler**): stage0 = the release named
in `bootstrap.txt` (2.6.0) for this machine (windows-x64.zip, linux-x64 / macos-arm64
.tar.gz), downloaded from GitHub once and cached in `compiler/build/` (`-Bootstrap <exe>` /
`--bootstrap <exe>` overrides; offline it falls back to an installed `stratac`). stage0
links stage1 with **its own** shipped runtime; from then on each stage first compiles
today's `lib/srt.strata` (`stratac object`) and links with that: stage0 → stage1 → stage2 →
stage3. **The build fails unless stage2 and stage3 are byte-identical** (and stage1 /
stage2 compile the same runtime object). stage3 ships as `bin/stratac`; console and
libstrata are built by it. build.ps1 also builds `lib/srt-linux-x64.o` and
`lib/srt-macos-arm64.o` (cross-compiling).

```
sh compiler/build.sh            # macOS (ARM64) / Linux (x86-64): the same bootstrap
sh compiler/tests/run.sh        # build + the same checks as run.ps1
sh compiler/install.sh          # ~/.local/share/strata, linked as ~/.local/bin/stratac
```

**Quick iteration on the compiler:** `compiler\bin\stratac.exe build compiler\src\stratac.strata`
→ `src\stratac.exe` (don't make a compiler overwrite its own running exe). Run the full
`run.ps1` before committing; CI checks Linux / macOS (and that the compilers Windows
cross-compiles for them equal the ones they build natively).

**Using the compiler:**
```
stratac new    <name>                                     # project: strata.toml + src/main.strata
stratac run    [target] [--release] [--force] [-- args]   # build and run
stratac build  [target] [--release] [--force]             # exe or dll
stratac check  [target]                                   # type-check only
stratac asm    [target] [--release]                       # print the assembly
stratac ir     [target] [--release]                       # print the IR
stratac object <file.strata> [out.o]                      # a module (no main) as an object file
stratac assemble <file.s> [out.o]                         # Strata's assembler on its own
stratac ast | tokens <file.strata>                        # debugging views of one file
--target windows-x64 | linux-x64 | macos-arm64            # build for another OS / CPU
```
A *target* is a `.strata` file, a project folder, a `strata.toml`, or nothing (the project in
the current folder). A single `.strata` file builds optimized into `<name>(.exe)` beside it
(and `<name>.o`). Libraries (`link "x"`, `libs`) are shared libraries, linked by Strata's
linker (Windows: x.dll / libx.dll in System32, `lib_dirs`, PATH; Linux: a soname; macOS:
the system frameworks / libobjc, else `@rpath/libx.dylib`).

**Projects (`strata.toml`)** — every key is documented at the top of `src/project.strata`:
`[project]` name / entry / output (`exe`|`dll`) / out_dir; `[build]` release, lib_dirs,
libs; `[windows]`/`[linux]`/`[macos]` per-platform libs. Builds are cached (an unchanged
project skips the link).

**Releasing a version** (the established process):
1. Bump `export string stratac_version()` in `compiler/src/version.strata` (and
   `editors/vscode/package.json`); add a `CHANGELOG.md` section; update this file.
2. `run.ps1` must pass (and CI). Commit to `main`, tag `vX.Y.Z`.
3. Verify from a clean checkout: `git worktree add <tmp> vX.Y.Z`, run its `run.ps1`, then
   `package.ps1 -Version X.Y.Z` there (the zip and the Linux / macOS tar.gz files).
4. `git push origin main vX.Y.Z`; `gh release create vX.Y.Z <3 archives> --title ... --notes ...`.
5. `install.ps1 -NoBuild` to update the machine's global `stratac`.
6. To let `src/` use the new version's features, bump `bootstrap.txt` to it.

---

## 4. How the compiler works

A strict one-way pipeline, one file per phase, phases talking only through data:

```
file.strata → lexer → parser → (module loader) → checker → lower → opt → arch/<cpu> ⇒ machine code (asm) → .o → linker (os/<os>, + lib/srt*.o) → exe / dll
```

| `compiler/src/` | Role |
|---|---|
| `token`, `ast` | shared data: tokens; AST nodes (`TypeNode`/`Expr`/`Stmt`/`Decl`), `Module`, `Program` |
| `lexer` | text → tokens. Newlines end statements (not inside `(`/`[`); `;` optional. Interns identifiers |
| `parser` | tokens → AST, recursive descent; nesting limit (`max_nesting`, 1,000) |
| `modules` | the loader: parses each imported file once → one `Program` + module table |
| `hashidx` | a small hash index (checker name tables, lexer interning) — Strata has no map type yet |
| `checker` | names + module visibility, types, `var` inference; writes each expr's type to `Expr.rtype` |
| `ir` | the native backend's IR: vregs (scalar types, ints kept sign/zero-extended to 64 bits), stack slots, labels, calls; a printer (`stratac ir`) |
| `lower` | typed AST → IR: C's arithmetic conversions, vector math inline, `srt_*` runtime calls, regions, function pointers (`call_indirect`), the target's struct-passing rules (Windows x64 `abi_*`, System V, Apple ARM64 `aapcs_*`) |
| `opt` | fold, slot forwarding + dead stores, CSE, copy propagation, DCE, flow cleanup, LICM, coalescing; `alloc_regs` (liveness + linear scan over a target `RegSet`) |
| `asm` | **the** assembler (any CPU): GNU-as text → bytes, symbols, relocations (`ObjFile`); sections, directives, labels, fixups; `assemble(text, arch)` hands each instruction to `arch/<arch>` |
| `arch/arm64` | **everything ARM64**: IR → LLVM-syntax assembly text (Apple's convention; locals from sp; lazy vregs; cmp+branch fusion; long-form branches in functions over 20k IR instructions), assembled by `asm`; the encoder (`arm64_instruction`, `arm64_fixup`: b / bl / b.cond / cbz resolved in `.text`, adrp / @PAGEOFF always relocations), byte-identical to clang |
| `arch/x64` | **everything x86-64** (one file per CPU): IR → instructions as `Opnd`s, encoded straight to machine code (`ins2` → `x64_encode`; printed as GNU-as AT&T text only for `stratac asm`), Windows x64 ABI; immediates / folded addresses ("lazy" vregs), cmp+branch fusion, stack probes; the encoder (`x64_instruction`, `x64_fixup`, rel32 jumps always) |
| `linker` | **the** linker entry (any OS): `write_object`, `new_link` / `link_object` / `link_lib` / `link_program`, handed to `os/<os>` |
| `os/windows` | **everything Windows** (one file per OS): COFF objects; Strata's linker: COFF objects (the program's, the runtime's `srt.o`, any gcc-made COFF) → a PE `.exe`; section merge, symbols, relocations (REL32±, ADDR64, ADDR32NB, ADDR32), imports resolved from DLLs' export tables (the system's, and `link "x"`'s found by `link_library`; no import libs), jump stubs, the `_strata_start` stub (`__getmainargs` → `main` → `exit`), fixed base 0x140000000; dlls (`link_dll`): export table, `.reloc` base relocations, base 0x180000000; import libraries, Microsoft format (`<name>.dll.a` for GNU ld, `<name>.lib` for MSVC) |
| `os/linux` | **everything Linux**: ELF objects; the ELF linker (static, or dynamic with libc / any `link "x"`; `.so` output), `_start` / `srt_syscall` stubs |
| `os/macos` | **everything macOS**: Mach-O objects; the Mach-O linker (executables and dylibs for dyld: stubs, __got, bind / rebase opcodes, export trie), SHA-256, the ad-hoc code signature |
| `native` | the native driver (`native_compile`, `native_target_why`; `native_arm64` for ARM64) |
| `core` | umbrella: `export import`s every phase = the compiler as a library (no `main`) |
| `project`, `build` | the build system: `strata.toml`; pipeline, cache, dll exports |
| `cheader` | a dll's C header for C / C++ hosts (`generate_header`; function types as `strata_fn<N>` typedefs) |
| `libstrata` | the public embedding API (`strata_*` exports) |
| `stratac`, `console`, `dump`, `version` | CLI front-end, explorer front-end, printers, version string |
| `host` | what the compiler needs from its host, as one `foreign` block: message sink (print vs capture), raw stdout, memory reset, lib/ lookup, one-pass string join, array free, binary files, float-literal bits; the OS: `strata_host_os`, `strata_exe_path`, `strata_make_dirs`, `strata_run_argv`. They are the `strata_*` functions at the end of `lib/srt.strata` (on its OS layer, `lib/srt/<os>.strata`) |

**Key ideas**
- **One backend, three targets.** Sugar is resolved in the checker; `lower` reads the typed
  AST. New language features go through `lower` (and the targets' code generators).
- **The runtime** is `lib/srt.strata` (Strata, compiled with `stratac object` into
  `lib/srt.o` / `srt-<target>.o`): `srt_*` functions (behaving exactly as the old C
  runtime did), structs always by pointer; what it needs from the OS is in
  `lib/srt/<os>.strata` (msvcrt + kernel32; syscalls; libSystem). Adding a builtin = a
  `srt_*` function there + a case in `lower_call`. It also holds the compiler's host
  functions (`strata_*`, see `host`): adding one = a declaration in `src/host.strata` +
  a function in `srt.strata` (and a release, before the compiler's own code can call it:
  stage0 links stage1 with its own runtime).
- **Evaluation order is left to right** (DESIGN.md §8b).
- **Modules** are parsed per file; every `Decl` records its module. The checker enforces
  visibility and gives **colliding private names** module-prefixed symbol names
  (`mods_shapes__helper`).
- **Messages** go through `strata_report` (printed by the CLI, captured by libstrata).
- **Performance rules learned the hard way:** never build strings with `s = s + x` in a
  loop (quadratic) — collect pieces and `strata_join` / `join_with`; walk left-deep
  operator chains in a loop, not recursively; long strings made by the runtime have their
  length remembered (`srt.strata`'s `len_put` / `str_length`), so `.len`
  / `substr` on them are O(1).

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
  `import gfx.Renderer` loads `<root>/gfx/Renderer.strata` (root = the main file's folder;
  else Strata's `lib/`: `import CrossPlatform`); **`when target_os == "windows" { ... }`**
  keeps code / imports for one target only (decided while parsing: `parser.strata`'s
  `when_top` / `when_stmt`; `target_os`, `target_arch`);
  imports are **not transitive**; `export import X` re-exports. Modules hold declarations
  only. Missing/private/unimported/conflicting names get errors that say how to fix them.
- **Globals:** `global int score = 0`, `export global ...`, `global var x = "s"` — any file,
  private unless exported, constant initial values (zero if none).
- **C interop:** `foreign { T name(params) }` declares functions, `struct`s (C layout,
  by value) and `const`ants (`const Color RAYWHITE = Color{...}`) defined outside Strata
  (a header named on the block is documentation); link names (`= "objc_msgSend"`);
  function pointers both ways (`fn(...) -> T`). See `examples/raylib.strata`,
  `examples/callbacks.strata`. `link "lib"`. `cast<T>` converts `string` ↔ pointers.
- **Designed, not built:** tagged unions + pattern matching, expression-bodied functions,
  default/named arguments, qualified names (`shapes.area`), module-level constants (outside `foreign`
  blocks), region-escape checking.

---

## 6. Embedding (engines, editors, tools)

`libstrata.dll` + `compiler/api/strata.h` (C), `strata.hpp` (C++), `Strata.cs` (C#,
P/Invoke). Installed to `<prefix>/include/` with `libstrata.dll.a` (GNU ld) and `libstrata.lib`
(MSVC), import libraries Strata writes itself (`src/implib.strata`). **Any engine may embed
it under any license** (`LICENSE-EMBEDDING.md`, the Classpath exception).

API: `strata_check` / `strata_check_source` (unsaved editor text),
`strata_build` / `strata_output_path`, `strata_diagnostics` (messages are captured),
`strata_set_libdir` (default: `lib/` next to the dll), `strata_reset` (frees all compiler
memory: engines can recompile indefinitely), `strata_version`. Not thread-safe.

A Strata project with `output = "dll"` exports exactly its entry module's `export`ed
functions and gets a generated `<name>.h` beside it (`src/cheader.strata`; on Windows
also `<name>.dll.a` + `<name>.lib`). Dlls are relocatable (Windows: `.reloc`; Linux `.so`:
R_X86_64_RELATIVE; macOS `.dylib`: rebase opcodes). A dll can hand a host a struct of
function pointers, and call the host's callbacks (`fn(...)` types).

---

## 7. The runtime (`compiler/lib/`, in Strata; GPL + runtime linking exception)

| File | Provides |
|---|---|
| `srt.strata` | the runtime, **in Strata** (`srt_print_*`, arenas, strings with remembered lengths, arrays, files, args, `srt_mat4_*` / `srt_quat_*`; exact float digits and exact float parsing with small big integers), plus the compiler's host functions (`strata_*`). `when`-imports its OS layer. build.ps1 / build.sh compile it with `stratac object` to `srt.o` (Windows), `srt-linux-x64.o`, `srt-macos-arm64.o` (gitignored, shipped in releases) |
| `srt/windows.strata`, `srt/linux.strata`, `srt/macos.strata` | the OS layers: msvcrt + kernel32; system calls (an mmap allocator, buffered stdout); libSystem (stdout buffered here too) |
| `CrossPlatform.strata` (+ `CrossPlatform/<os>.strata`) | **the CrossPlatform library**: `import CrossPlatform` — window, system, files, programs; Win32, X11, Cocoa |

**Rule:** every stage compiles today's `lib/srt.strata` first, so `srt.strata` can change
freely (it may only use stage0's language features); a new host function the compiler
itself calls must wait for a release (stage0 links stage1 with its own runtime).

---

## 8. Examples (`compiler/examples/`)

`hello` (flagship), `run1`, `arena`, `vectors`, `matrix`, `arrays`, `switch`, `strings`,
`interop`, `list` (alloc + null), `casts`, `prelude`, `loops` (break/continue),
`modules` + `greetlib`, `modules2` + `mods/` (the module system), `foreign` (C structs /
constants / link names in foreign blocks), `callbacks` (function pointers: vtables, C
calling back into Strata), `order` (evaluation order), `platform` + `platform_window` (the
CrossPlatform library: system / files / programs, and a window), `when` (compile-time
conditions).
Graphical (open a window; build, don't auto-run): `window`, `sprite`, `balls` — raylib
through the `raylib.strata` module (a foreign block), native. Error cases: `errors`, `breakerr`, `modvis`, `modload`, `modpriv`.
`abi` (native-backend corners: struct passing, 7-argument calls, narrow / unsigned
arithmetic, shifts, floats, short-circuiting, pointers).

---

## 9. Tests (`compiler/tests/run.ps1`: 57 checks; `run.sh`: the same on macOS / Linux)

1. **Bootstrap + fixpoint** (runs `build.ps1` / `build.sh`: native stages, stage2 == stage3).
2. **Goldens:** `tests/<stage>/<name>.expected` vs `stratac <stage> examples/<name>.strata`,
   byte-for-byte; stages `tokens`, `ast`, `check`, `run` (what differs by OS:
   `<name>.expected.linux` / `.expected.macos`, read by run.sh). Add a test by adding a
   `.expected` file.
3. **Projects:** each `tests/projects/<name>/` is run (or, for a dll, built) with `--force`
   against `expected.txt`, then must rebuild as "up to date". `native` (per-platform libs,
   a subfolder module), `lib` (dll, with a function-pointer table), `multi` (modules
   sharing state and CrossPlatform), `badtoml` (project-file errors), `pure` (a debug
   build, unoptimized, of a multi-module program).
4. **No C compiler:** with gcc off PATH, five examples and `projects/pure` build and print
   their goldens, `window` links against a lone copy of libraylib.dll, and the compiler
   builds itself (the result runs hello). **raylib:** `window`, `sprite`, `balls` build
   (skipped without raylib). **Assemblers:** ten examples' x86-64 objects must disassemble
   to the same instructions as GNU as's (needs objdump); every example's ARM64 code must
   equal clang's (needs LLVM); a build's machine code must equal the `asm` + `assemble`
   path's. **Cross-compiling:** hello for linux-x64 (ELF) and macos-arm64 (signed
   Mach-O). **CrossPlatform's window:** opened and closed natively (Windows; Linux on Xvfb;
   macOS). `stratac asm` smoke test.
5. **Embedding** (`tests/embed/`): C, C++, C# hosts using libstrata (incl. 300
   check+reset cycles with flat memory, builds), and a C host calling a Strata-built dll
   (its function table, and a C callback).
6. **Performance & limits:** 20k lines must check in < 3 s; 1,001-deep nesting must be a
   clean error; a 100,000-term expression must build in < 3 s.
7. **CI** also checks the compilers Windows cross-compiles for Linux / macOS equal the
   ones those OSes build natively (what the release archives are made from).

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
| Native build, 20k-line single file | 0.47 s (2.1.0; 2.0.0: 0.97 s; through C + gcc -O2: 3.6 s) |
| Native build, a small program | 62 ms (through C + gcc: 308 ms); the exe is 12 KB |

---

## 11. Known limitations

- `link "x"` in a source file is not per-platform (wrap it in `when target_os == ...`, or
  use a project's `[windows]` / `[macos]` / `[linux]` sections).
- Shared libraries keep the project's name on every OS (`mathlib.so`, not
  `libmathlib.so`), so C hosts on macOS / Linux link them by path, not `-lmathlib`.
- `embed/csharp` is skipped by `run.sh` (Strata.cs not set up for macOS / Linux yet).
- **Targets:** x86-64 Windows, x86-64 Linux, ARM64 macOS (exes and dlls each). Strata can't
  read C headers: declare what you use in `foreign` blocks. Windows executables have a
  fixed base (no ASLR relocations yet); no unwind tables, no debug info yet (no stepping
  in a debugger). Huge functions (liveness bitsets over 4M words) skip register
  allocation. u64 ↔ float conversions of values ≥ 2^63 are treated as signed on x86-64.
  Native exes reserve an 8 MB stack (IR slots don't share stack space yet, spilled vregs
  do). Static libraries (`.a` / `.lib` archives) can't be linked: shared libraries only.
- A `global` can't be initialized with a function's address (assign it at runtime).
- **MSVC:** `libstrata.lib` is generated (Microsoft import-library format) but hasn't been
  linked by MSVC's own `link.exe` yet (no MSVC on this machine); GNU ld links it fine.
- **libstrata** is single-threaded.
- **Strings** are NUL-terminated C strings: no `\0` inside a string.
- **`for i in 0..n`** re-evaluates `n` each iteration (a semantics decision is pending).
- **No module constants** (`global` variables exist); top-level `const` is a local of `main`.
- **Memory** is mostly the AST (`Expr` 104 B, `Stmt` 184 B); arenas never free early.

---

## 12. What's next (and open decisions)

**Done this era (see CHANGELOG):** 1.0 self-hosting · 1.1 module system · 1.2 build system
· 1.3 embedding API · 1.4 compiler 25–540× faster · 1.5 break/continue, incremental parallel
builds, hardened limits · 1.6 stratac on Windows, macOS and Linux (crossplatform.h, C seed)
· **2.0 the native backend: x86-64 code + an optimizer, Strata's own** · **2.1 Strata's own
assembler + COFF writer + linker: native builds need no C compiler.** · **2.2 the native
runtime in Strata (`foreign` blocks, `global` variables).** · **2.3 C libraries without C:
structs / constants in `foreign` blocks, Strata's linker links DLLs (raylib, no gcc).** · **2.4
the compiler compiles itself natively (no C compiler to build Strata on Windows).**

**The independence road (the user's chosen direction; done through step 6 + C removed):**
1. ~~**Object files directly** (COFF): an x86-64 encoder in Strata, no assembler.~~ Done
   (`x64asm.strata`, `coff.strata`; matches GNU as instruction for instruction).
2. ~~**Strata's own linker** (PE executables, imports straight from system DLLs): no gcc
   for native builds.~~ Done (`pelink.strata`; `run.ps1` builds with gcc off PATH).
3. ~~**The runtime in Strata**~~ Done for the native backend (`lib/srt.strata`, with
   `foreign` + `global`); it still calls msvcrt.dll (an OS DLL) for memory, files and
   `puts`. Next level: straight to kernel32 (`VirtualAlloc` / `WriteFile`) / syscalls.
4. **C header import** (declarations → Strata; a small C shim for inline functions /
   code macros): raylib & engines natively. `foreign` blocks already let a program
   declare what it uses by hand (functions, structs, constants): raylib works that way.
5. ~~**More targets**~~ Done (2.6.0): ARM64 macOS, x86-64 Linux. (Linux ARM64 or Windows
   ARM64 would be an `os/` + ABI combination of what exists.)
6. ~~**Self-compiling natively**~~ Done everywhere (2.4.0 Windows, 2.6.0 macOS / Linux);
   ~~the C backend and seed~~ deleted after 2.6.0. Next: the optimizer keeps improving
   (IR slot sharing, inlining, better allocation, SIMD for vec math, tail calls).
Also: debug info (CodeView / DWARF) so native builds can be stepped in a debugger.

**Other candidates:**
1. **Tagged unions + pattern matching** (the next big language feature; pairs with `switch`).
2. **Commercial-engine integrations** (user: "later"): Unity / Unreal plugins (a `.lib`
   exists now);
   Godot GDExtension (M6).
3. `stratac watch` (keep the program in memory, rebuild on save) → an LSP later.
4. Language sugar: qualified names, module constants/globals, default/named args.
5. SoA / `#soa` arrays (M4), hot-reload runtime (M5).
6. Housekeeping: `bootstrap.txt` is 2.6.0 now, so the compiler's code may use `when`,
   function pointers, link names, `continue`; clean up the D--isms in `src/` (paren
   conditions, `;`, `0 - 1`) and replace host-state workarounds with globals.

**Open decisions for the user:** does `for i in 0..n` evaluate `n` once (Go/Rust) or each
iteration (today)? · which of the candidates comes next.

---

## 13. Working notes (for whoever picks this up — human or agent)

- **The bootstrap rule:** the compiler's own source may only use features of the release
  in `bootstrap.txt` (2.6.0), and only the runtime / host functions the pinned release's
  runtime objects provide (stage0 links stage1 with them). `lib/srt.strata` is first
  compiled by stage1, so it may use anything the current source supports. To use a new
  feature in `src/`: release a version with it, bump the pin.
- **OS-specific code goes in the runtime's OS layers** (`lib/srt/<os>.strata`, behind
  `srt_os_*`) or in `lib/CrossPlatform/<os>.strata`; target-specific code generation in
  `arch/` and `os/`. No `system()`, `cmd.exe` or `.exe` literals in the compiler: ask
  `host_os()` / `exe_ext()` / `dll_ext()` / `target_os()`.
- **Edit `compiler/src/*.strata` directly.**
- **Keywords can't be identifiers** — e.g. `link`, `region`, `cast`, `sizeof`, `break`,
  `var`, `import`.
- **Decimal constants for big hex values** (Strata has no hex literals in some places of
  the compiler's style): check them with Python — a wrong one cost a CI round (the Mach-O
  signature magic).
- **Debugging:** `stratac ir file --release` / `stratac asm file --release` show each
  stage; `--target` shows another CPU's code; LLVM's tools read the Mach-O / ELF output.
- **Benchmarks:** the first run of a freshly built exe is slowed by Windows scanning it —
  take the best of several runs.
- **Imports aren't transitive**; front-ends `import core`.
- **Don't let a compiler overwrite its own running exe** (build into another path).
- **Goldens are LF;** the test runner normalizes line endings.
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
