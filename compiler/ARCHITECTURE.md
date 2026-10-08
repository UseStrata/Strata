# Strata Compiler Architecture

> How the Strata compiler is built, and the rules that keep it from turning into
> spaghetti. Read this before touching `src/`. The *language* design lives in
> [`../website/design/DESIGN.md`](../website/design/DESIGN.md); this is the
> *implementation*.
>
> This mirrors **D--'s proven, self-hosted compiler** (a clean multi-pass pipeline).
> We are not inventing an architecture — we are copying one that already works.

---

## 1. The one idea: a strict, linear pipeline

A compiler turns to spaghetti when phases reach into each other and share mutable
state. The cure is a **one-way pipeline of passes**, where each pass has a single job
and phases communicate **only through data structures**, never by calling into each
other's internals.

```
foo.strata
   │
   ▼  lexer        text → token stream
 tokens
   │
   ▼  parser       tokens → AST            (recursive descent)
  AST
   │
   ▼  checker      AST → typed AST         (name resolution, types, inference, regions)
typed AST
   ├──────────────────────────────┐
   ▼  lower    typed AST → IR      ▼  codegen   typed AST → C source   (the C backend)
  IR                              foo.c
   │                               │
   ▼  opt      IR → better IR,     ▼  gcc / cc / clang
   │           registers          native executable
   ▼  x64      IR → assembly       (the native backend, the default where it can)
 foo.s  →  assembler + linker  →  native executable
```

Two backends share everything up to the typed AST. The native one is Strata's own:
`ir.strata` is target-independent, so another CPU is another `x64.strata`-like file.

Data flows **down only**. A later phase reads the previous phase's output; **no phase
ever reaches backward or sideways.**

---

## 2. File layout (mirrors D--)

**The compiler is written in Strata** (since v1.0.0; it was originally written in D--, removed in
2.0 and still in git history). `build.ps1` (Windows) / `build.sh` (macOS, Linux) bootstraps it: stage0 (a
pinned `stratac` release, see `bootstrap.txt`; on macOS / Linux the C seed in `seed/`)
compiles `src/` (stage1), stage1 compiles `src/` again (stage2), and the two must emit
identical C (the fixpoint).

```
compiler/
├─ ARCHITECTURE.md      ← this file
├─ build.ps1            bootstraps + builds all artifacts into bin/ (2 exes + libstrata.dll)
├─ build.sh             the same on macOS / Linux, from seed/ (libstrata.dylib / .so)
├─ bootstrap.txt        the release version stage0 is pinned to (Windows)
├─ seed/                the C seed: a stratac compiled to C + its headers (macOS / Linux stage0)
├─ api/                 libstrata's project file + the embedding API: strata.h, strata.hpp, Strata.cs
├─ src/
│  │  ── the CORE (no main; the "library") ──
│  ├─ token.strata      shared data: token kinds + Token struct
│  ├─ ast.strata        shared data: node kinds (tagged union) + node structs, modules
│  ├─ lexer.strata      text → tokens
│  ├─ parser.strata     tokens → AST
│  ├─ modules.strata    the module loader: files → one Program + module table
│  ├─ hashidx.strata    a small hash index (the checker's name tables, the lexer's interning)
│  ├─ checker.strata    AST → validated/inferred AST (incl. module visibility)
│  ├─ codegen.strata    typed AST → C                     (the C backend)
│  ├─ ir.strata         the native backend's IR (target-independent)
│  ├─ lower.strata      typed AST → IR (+ the C calling convention's struct rules)
│  ├─ opt.strata        the optimizer + register allocator
│  ├─ x64.strata        IR → x86-64 assembly (Windows)
│  ├─ native.strata     the native backend's driver: lower → opt → x64
│  ├─ core.strata       umbrella module (`export import`s every phase), main-free
│  │  ── the build system (on top of the core) ──
│  ├─ project.strata    reads strata.toml into a Project
│  ├─ build.strata      the build pipeline (native or C -> exe/dll) + the build cache
│  ├─ strata_host.h     C the compiler imports: messages, memory, and the OS (via lib/crossplatform.h)
│  │  ── shared front-end utility ──
│  ├─ dump.strata       renders core data (tokens/AST) to text
│  │  ── front-ends (thin; each has top-level code = its main) ──
│  ├─ stratac.strata    front-end #1: the CLI (tokens, ast, check, emit, asm, ir, build, run)
│  ├─ libstrata.strata  front-end #3: the public C API (libstrata.dll, for engines)
│  └─ console.strata    front-end #2: the explorer console
├─ bin/                 build output: stratac(.exe), console(.exe), libstrata.dll/.dylib/.so
├─ build/               bootstrap compilers (cached release + stage1/2)
├─ lib/                 the C runtime the OUTPUT links against (arena.h, math, prelude)
├─ examples/            sample .strata programs
└─ tests/              golden-file tests, one dir per stage (tokens/, ast/, check/, run/, emit/)
```

- The data modules (`token`, `ast`) hold shared definitions; the others are passes.
- **The core (`core.strata` and everything it re-exports) has no `main`.** Front-ends
  (`stratac`, `console`, the DLL) include the core and add the shell. This is the
  exe/lib/LSP split from §11, in force from day one.
- **If any phase file grows past ~1000 lines, that's the signal to split it by
  concern** (e.g. `checker` → name-resolution + type-check), never to cram more in.

---

## 3. The phases (each: reads → produces, and what it must NOT do)

### Lexer — `lexer.strata`
- **Reads** source text. **Produces** a flat token stream.
- Handles: keywords, identifiers, literals, operators, newline-as-terminator, comments.
- **Must NOT** know about grammar, types, or the AST. Only characters → tokens.

### Parser — `parser.strata`
- **Reads** tokens. **Produces** the AST. **Recursive descent** (readable, hand-written,
  matches D--).
- This is where **surface sugar desugars**: top-level statements are collected into an
  implicit entry point; `f(x) = expr` becomes a normal function body.
- **Must NOT** resolve names, check types, or touch C. It only builds tree shape.

### Checker — `checker.strata`  (a.k.a. sema)
- **Reads** the AST. **Produces** a typed/annotated AST + symbol tables.
- Does: **name resolution** (scopes), **type checking**, **`var` inference**,
  **default/named-argument resolution** (at the call site), **method/UFCS resolution**
  (`e.f(x)` → `f(e, x)`), and later region/escape checks and generic-instantiation
  collection (monomorphization set).
- Reports **all** errors (recovering, not stopping at the first — D--'s practice).
- **Must NOT** emit C. Its job is to make the AST correct and fully typed.

### Codegen — `codegen.strata`
- **Reads** the typed AST. **Produces** C source text (readable C).
- Emits: functions, structs, tagged unions (`struct { tag; union; }`), `match` → `switch`,
  arena calls, monomorphized generic instantiations, vector-math calls.
- **Must NOT** make decisions the checker should have made. If codegen needs to "figure
  something out," that logic belongs in the checker. Codegen is a **pure translation.**

### The native backend — `ir`, `lower`, `opt`, `x64`, `native` `.strata`
- **`ir.strata`**: the intermediate representation. Per function: instructions over
  unlimited *virtual registers* (vregs) of scalar types (i8..u64, f32, f64; pointers are
  u64), stack *slots* for aggregates, labels, jumps, branches, calls. Invariant: an
  integer vreg holds its value sign/zero-extended to 64 bits. A vreg may be assigned more
  than once (a variable); the optimizer only rewrites single-definition vregs.
- **`lower.strata`**: typed AST → IR. Gives every construct its meaning: scalars in
  vregs (in a slot if their address is taken), aggregates in slots handled by address,
  C's usual arithmetic conversions (float literals are f64; results match the C
  backend's builds), vector math expanded to float ops, runtime calls (`srt_*` in
  `lib/srt.c`) for strings / arrays / arenas / matrices / I/O, regions freed on every
  exit. Struct passing follows the target's C convention (`abi_*`, Windows x64 today).
  Refuses (with a reason) what it can't do yet — C headers — and the build uses C.
- **`opt.strata`**: passes to a fixed point (fold, slot forwarding + dead stores, CSE,
  copy propagation, dead code, flow cleanup, loop-invariant motion, coalescing), then
  `alloc_regs`: liveness → live intervals → linear scan over the target's `RegSet`
  (callee-saved registers, plus scratch registers for values not live across a call).
- **`x64.strata`**: IR → GNU-as AT&T assembly for Windows x64: frame layout, the calling
  convention, immediates and folded addresses ("lazy" vregs never get a home),
  compare+branch fusion, stack probes. **`native.strata`** drives lower → opt → x64.
- **Must NOT**: lower must not know the CPU (beyond the ABI rules); the target must not
  know the language. Test: every run golden, through each backend, must print the same.

### Driver — `stratac.strata`
- CLI + orchestration **only**. Reads a file, runs the passes in order, invokes the C
  compiler, runs the binary. **Zero language logic lives here.**

### Runtime — `lib/` (not part of the compiler binary)
- Header-only C the *output* links against: `arena.h`, math library, prelude. Kept at the
  edge; the compiler emits calls into it.

---

## 4. The contracts: shared data structures

Phases only ever communicate through these. Get them right and the passes fall out.

- **Token** (`token.strata`) — kind + text + source span.
- **AST node** (`ast.strata`) — a **tagged union**: a `kind` enum + the per-kind data.
  Every pass traverses it with a `switch` on `kind`. **This is the spine — design it
  first.** (Polymorphism via tag + switch, *not* inheritance — D--'s explicit stance.)
- **Type / Symbol / Scope** (checker-owned) — the tables name-resolution and typing build.
- **Diagnostic** (`diag`) — a located message (span + text + severity). **All errors from
  every phase go through this one module** — never scatter `print`/panic error handling
  through the passes.

---

## 5. Anti-spaghetti rules (the point of this document)

1. **One pass, one job.** Never type-check in the parser; never emit C in the checker.
2. **Data structures are the only contract.** No phase calls another phase's internals or
   shares mutable globals with it.
3. **Unidirectional flow.** Later reads earlier; never the reverse. No cycles.
4. **Thin driver.** All orchestration in `stratac.strata`; no logic anywhere near it.
5. **Centralized diagnostics.** One module, source spans, error recovery — no scattered
   error handling, no panics inside passes.
6. **Design the AST first.** It's the spine; node kinds drive every pass.
7. **Every stage is independently runnable & testable** (see §6). This is *the* discipline
   that kept D-- clean.
8. **No premature IR.** Typed AST → C directly (D-- does this). Add an intermediate
   representation only when a concrete need forces it — not on spec.
9. **Balanced phases.** A phase past ~1000 lines gets split by concern, not stuffed.

---

## 6. Each stage runnable & testable (the key habit)

The driver exposes a subcommand to dump each stage's output, so any phase can be
inspected and tested in isolation:

```bash
stratac tokens foo.strata    # lexer output
stratac ast    foo.strata    # parser output
stratac check  foo.strata    # checker: types + errors, no codegen
stratac emit   foo.strata    # the generated C
stratac run    foo.strata    # full pipeline: compile (tcc) + run
stratac build  foo.strata    # release build (gcc/clang -O2)
```

**Testing:** `tests/` holds **golden files** — for each example, the expected tokens /
AST / C. Runs compare byte-for-byte (D--'s proven method); a diff is a regression. This
is what stops a change in one phase from silently corrupting another.

---

## 7. Milestone-1 build order (a thin vertical slice first)

The biggest lesson from D--: **get a tiny program running end-to-end early**, then
deepen each phase — don't perfect the lexer before you've ever emitted C.

1. ✅ `token.hmm` + `lexer.dmm` + `stratac tokens` (+ golden tests). *Done — significant
   newlines, `..` range, types-first tokens; validated by `tests/run.ps1`.*
2. ✅ `ast.hmm` + `parser.dmm` + `stratac ast`. *Done — recursive descent for structs,
   enums, types-first funcs, `var`/typed decls, control flow (`if`/`while`/`for..in`,
   paren-free with the `no_brace` rule), `..` ranges, top-level code → `Main`. Core split
   into `core.dmm` + front-ends `stratac`/`console`; `libstrata.dll` proven. Golden-tested.*
3. ✅ **Minimal `codegen.dmm`** — functions, arithmetic, `if`/`while`/`for..in`, `return`,
   `var` (via `__auto_type`), and a temporary `print`. *Done — `stratac run run1.strata`
   compiles to C via gcc and runs end-to-end; golden-tested (`run/run1`).*
4. ✅ `checker.dmm` — name resolution (linked-list scopes), type checking, arity,
   assignability, `var` inference (written back to the AST for codegen), `stratac check`.
   *Done — errors are located + recovering; golden-tested (`check/run1`, `check/errors`).*
5. ✅ `lib/arena.h` runtime + structs + `arena()` / `.new(T)` / `region { }` lowering.
   *Done — chunked arena (pointers stay stable), struct codegen, `.`→`->` auto-deref via
   the checker's `rtype` annotation on expressions; golden-tested (`run/arena`).*
6. ✅ **Milestone 2: first-class math.** `vec2/3/4`, `mat4`, `quat`; constructors,
   component-wise `+`/`-`/`*`, scalar scale, `.x/.y/.z/.w` **and swizzles** (`v.xy`, chained),
   `mat4 * vec4`, `mat4 * mat4`, `quat * quat`, and builtins (`dot`/`cross`/`length`/
   `normalize`, `mat4_translate/scale/rotate/perspective/look_at`, `quat_axis_angle/
   rotate/to_mat4/normalize`). Operators lower to `smath.h` calls via the checker's
   `rtype`. The flagship `hello.strata` runs end-to-end. Golden-tested.
7. ✅ **Strings + C interop.** `string` = C `const char*`; concat (`+`), `.len`, `==`/`!=`
   via `lib/sstr.h`. **`import "h.h"` / `import <h.h>`** emits `#include` and enables calling
   external C functions directly (checker treats unknown calls as external C once a header is
   imported). Golden-tested (`run/strings`, `run/interop` calling libc `puts`/`abs`).
8. ✅ **Milestone 3: raylib window.** A `link "lib"` directive adds `-llib` to the build;
   unknown *names* (e.g. `RAYWHITE`) resolve as external C symbols when a header is imported.
   [`examples/window.strata`](examples/window.strata) — `import <raylib.h>` + `link` — builds
   to a single native `.exe` (raylib installed via msys2). It's a GUI demo, so it's built (not
   golden-run) in CI. *Next: a prelude (input/time helpers), C struct/enum binding for engine
   types, then map Strata `vec2` ⇄ raylib `Vector2`.*
9. ✅ **Dynamic arrays (`T[dynamic]`).** Array literals `[a, b, c]`, `.push(v)`, `.len`,
   indexing (incl. lvalue: `xs[i].field = ...`), and `for x in xs` iteration. Type-erased
   `Array` runtime (`lib/sarr.h`); the checker tracks the element type. Works for structs,
   so **entity lists** work (see `examples/balls.strata` — a `Ball[dynamic]` with vec2
   physics + raylib). Golden-tested (`run/arrays`).
10. ✅ **Enums + `switch`.** Enums compile to C enums; `switch subject { case A: ...
    case B, C: ... default: ... }` with **no fall-through** (a `break` per case) and
    multi-value cases. Works on ints and enums — the AST-dispatch pattern a self-hosted
    compiler needs. Golden-tested (`run/switch`).
11. ✅ **Prelude + modules.** Prelude helpers (`min`/`max`/`clamp`/`lerp`/`PI`,
    `lib/sprelude.h`). **Modules:** `import Name` pastes `Name.strata` (dotted paths →
    folders; deduplicated, recursive) — the driver's module preprocessor mirrors D--'s
    `#include`. `export` marks decls public (intent; enforcement later). *(Superseded
    after 1.0.0 by a real module system; see HANDOFF.md §5.)* Golden-tested
    (`run/prelude`, `run/modules`). **With multi-file + switch + arrays, Strata can now
    express a compiler — self-hosting is unblocked.** *Next: port a module (e.g. the lexer)
    to Strata, or tagged unions / SoA.*

Only after this thin slice runs do we add math types (milestone 2), then the backlog
features — each slotting into the phase it belongs to, never sprawling across all of them.

---

## 8. Where each design feature lives (so nothing sprawls)

| Feature | Phase that owns it |
|---|---|
| newline termination, literals | lexer |
| top-level-code = main, expr-bodied `= expr` | parser (desugar) |
| `var` inference | checker |
| default / named arguments | checker (call-site resolution) |
| methods / UFCS | checker (rewrite `e.f(x)` → `f(e,x)`) |
| tagged unions + `match` | ast + checker + codegen |
| generics | checker (collect instantiations) + codegen (emit specialized C) |
| arenas / regions | codegen + `lib/` runtime |
| vec/mat/quat + operators | checker (types) + codegen + `lib/` math |

---

## 9. How production compilers compare (C++: Clang & GCC)

Our pipeline isn't a toy shortcut — it **is** the front end of every real compiler.
Big C++ compilers use the same phase separation, then add stages we deliberately skip:

```
Clang/LLVM:  lexer → parser+Sema → Clang AST → CodeGen → LLVM IR → (opt passes) → backend → machine code
GCC:         lexer → parser → GENERIC(AST) → GIMPLE(IR) → (opt passes) → RTL → machine code
Strata:      lexer → parser → checker → typed AST → codegen → C  →  [ tcc/gcc/clang does the rest ]
```

Two takeaways:

1. **Same skeleton.** Lexer → parser → semantic analysis → codegen is universal. Our
   `checker` is their "Sema". We're following the standard, not improvising.
2. **They add IRs; we borrow one.** Clang lowers to **LLVM IR**, GCC to **GIMPLE/RTL**,
   so they can optimize and target many CPUs. **Strata's IR is C** — we emit it and let
   the C compiler provide all the optimization and machine-code backend for free. That's
   the entire payoff of compile-to-C: reuse LLVM/GCC's middle and back end.
3. **Where C++ compilers get tangled — and we don't.** Clang has to *interleave* its
   parser and Sema because C++'s grammar is context-sensitive (you can't parse it without
   type info — templates, the "most vexing parse"). That entanglement is forced by the
   *language*. Strata's grammar is designed to parse cleanly **without** semantic feedback,
   so parser and checker stay fully separate. We get to keep the separation C++ can't.

---

## 10. Toolchain & on-disk layout

A C/C++ compiler is a **driver** that runs a chain of programs — preprocessor → compiler
→ assembler → linker. Strata does the compiling itself and, for now, borrows the C
toolchain's assembler and linker:

```
stratac run foo.strata                         (native backend: x86-64 Windows, no C headers)
  → (in-process) lexer → parser → checker → lower → opt → x64  → foo.s
  → gcc foo.s <install>/lib/srt.c -o foo.exe     (assemble + link with the runtime)

stratac run foo.strata --backend c             (C backend: any platform, C interop)
  → ... → checker → codegen → foo.c → gcc/cc -O2 foo.c -I <install>/lib -o foo
```

**The road to depending on nothing but the OS** (each step keeps the C path working):
write object files directly (no assembler) → Strata's own linker (no gcc for native
builds) → the runtime (`srt.c`, `lib/*.h`) rewritten in Strata on OS calls (no libc) →
C header import (C libraries / engines natively) → ARM64 and Linux / macOS targets →
the compiler built by its own native backend (the C seed becomes optional).

**Install layout** — one monolithic install *home* on `PATH`, runtime beside the exe,
mirroring D--'s `install.ps1` (the exe finds `lib/` next to itself, so nothing else needs
configuring). The **source repo** (`compiler/` + `website/`) stays separate and modular;
only the *installed toolchain* is monolithic. Built by `build.ps1`, deployed by
`install.ps1`.

```
%LOCALAPPDATA%\Programs\strata\   (per-user; -System → %ProgramFiles%\strata; -Prefix to override)
├─ stratac.exe         the compiler CLI (stage2 of the bootstrap)
├─ console.exe        the explorer front-end
├─ libstrata.dll      the core as a shared library (for embedders)
└─ lib\               the runtime the OUTPUT links against (driver passes -I <home>\lib)
   ├─ arena.h …       header-only C runtime (see lib/README.md)
   └─ srt.c           the entry points natively compiled programs call
```

The runtime `lib/` lives in the home for the *compiled program's* sake, not the
compiler's — `stratac.exe` is a self-contained monolith; `lib/` is what generated C links
against.

Rules:
- **Native first**: `--backend auto` (the default) builds natively when the native
  backend can (`native_target_why`, `lower_program`'s reason otherwise) and with C when
  it can't; `--backend native|c` forces one.
- **The C toolchain** is found as `gcc` (Windows), `cc`, or `$STRATA_CC`.
- `stratac emit` / `asm` / `ir` print what each backend generates.

---

## 11. Embedding: exe now, library & LSP later

Real compilers aren't just exes — the exe is a thin driver over libraries. `cl.exe`
loads `c1/c1xx/c2.dll`; Clang ships `libclang`; Roslyn *is* a library with `csc.exe` on
top. IDE features (Visual Studio IntelliSense, VS Code) use the compiler **in-process as
a library**, usually wrapped in a **language server** (clangd, rust-analyzer) that editors
reach over **LSP**.

**The payoff of our clean phases: one core, three faces.** Because the phases are a
reusable core and the driver is thin (rule #4), the same code can be shipped as:

1. **`stratac` (exe)** — the CLI driver. *Milestone 1.*
2. **`libstrata` (.dll/.so)** — an API exposing lex/parse/check/codegen + the AST, for
   engines embedding/hot-reloading Strata or tools that want the tree. *Later.*
3. **`strata-lsp`** — a language server built on the *same core*, giving VS Code / any
   editor live diagnostics, completion, go-to-def over LSP. *Later.*

A spaghetti compiler can only ever be #1. Keeping the driver thin and the phases pure is
what makes #2 and #3 possible without a rewrite — so we don't foreclose them now.

> Related: **tcc ships as `libtcc`** (`tcc_compile_string` / `tcc_run`), so the backend
> hand-off can become an **in-process library call** rather than spawning `tcc.exe` —
> the natural mechanism for in-memory `stratac run` and milestone-5 hot-reload.
