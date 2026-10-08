# Strata™

A statically-typed, compiled programming language **for games and real-time software**.

> *"Safer than C, simpler than Rust — the control C gives games, without the footguns
> or the borrow-checker fight."*

Strata compiles to **native x86-64 code itself** — its own code generator and optimizer
(Windows today; more CPUs and systems to come) — or to **plain C**, for every platform
and for calling C libraries. The long-term goal: a toolchain that depends on nothing but
the operating system. Its four ideas:

- **Arena / region memory** — no garbage collector, no manual `free`. *Everything in a
  region dies together.*
- **First-class data-oriented & math types** — `vec2/3/4`, `mat4`, quaternions, opt-in SoA.
- **Seamless C interop** — it *is* C underneath; targets any C engine + Godot (GDExtension).
- **Hot-reload** — a pluggable runtime, following the Handmade/Jai host-module pattern.

```strata
struct Entity { vec3 pos; vec3 vel; int hp }

vec3 update(Entity* e, float dt) = e.pos + e.vel * dt

var world = arena()
var e = world.new(Entity)
e.vel = vec3(1, 0, 0)

for i in 0..60 {
    e.pos = update(e, 0.016)
}
```

## Status

**v1.0.0: self-hosted.** The compiler is written in Strata and compiles itself.

- ✅ lexer, parser, type checker, C codegen
- ✅ arena/region memory, structs, functions, control flow
- ✅ first-class math: `vec2/3/4`, `mat4`, quaternions, swizzles
- ✅ strings, and **C interop** (`import` a header, `link` a library, call C directly)
- ✅ **dynamic arrays** (`T[dynamic]`: literals, `push`, `len`, indexing, `for x in xs`) — entity lists
- ✅ **enums + `switch`** (multi-value cases, no fall-through) — state machines
- ✅ **modules**: every file is a module, private by default; `export` to publish, `import gfx.Renderer`
  to use, `export import` to re-export
- ✅ a small **prelude** (`min`/`max`/`clamp`/`lerp`/`PI`)
- ✅ `alloc(value)` + `null` — heap-allocated node graphs (e.g. an AST)
- ✅ **games written in Strata** — a raylib window ([`window.strata`](compiler/examples/window.strata))
  and an **arrow-key-driven sprite** ([`sprite.strata`](compiler/examples/sprite.strata), movement
  computed with Strata's own `vec2` math) build to single native binaries
- ✅ `cast<T>(x)`, `sizeof(T)`, string/file built-ins (`substr`, `read_file`, `args()`, ...)
- ✅ **self-hosted**: `stratac` is written in Strata ([`compiler/src/`](compiler/src/)),
  bootstrapped from a pinned release and verified to reproduce itself byte-for-byte
- ✅ syntax highlighting for VS Code and Visual Studio ([`editors/`](editors/))
- ✅ **projects**: `stratac new`, a `strata.toml` (per-platform libraries, C sources, exe or dll), cached builds
- ✅ `break` / `continue`, and incremental, parallel project builds (edit one function: ~1 s on an 81k-line project)
- ✅ **embeddable**: `libstrata.dll` + `strata.h` (C), `strata.hpp` (C++), `Strata.cs` (C#) for engines and tools;
  Strata-built dlls come with a generated C header
- ⏳ next: tagged unions + pattern matching, SoA arrays, hot-reload

The compiler is called **`stratac`**. It is written in Strata and compiles to plain C.
It was bootstrapped from D-- (a separate C-compiling language); the D-- version is kept
as the frozen seed that starts the build.

## Layout

```
compiler/   the stratac compiler (written in Strata) — see compiler/ARCHITECTURE.md
editors/    syntax highlighting (VS Code, Visual Studio)
website/    design + documentation                 — see website/design/DESIGN.md
Strata.md   the founding project plan
```

## Build & run

Requires a C compiler: `gcc` (MinGW) on Windows; `cc` (clang or gcc) on macOS and Linux,
or set `STRATA_CC`. (On x86-64 Windows, Strata generates the machine code itself and uses
the toolchain only to assemble and link — `--backend c` goes through C instead.) To just
*use* Strata, grab a release, or run the installer below.

The compiler is written in Strata, so the build bootstraps it. On **Windows** it downloads
a pinned `stratac` release once (see `compiler/bootstrap.txt`). On **macOS / Linux** it
compiles the C seed in `compiler/seed/` (a `stratac` compiled to portable C, see its
README). Either way: stage0 → stage1 → stage2, and stage1 and stage2 must agree.

```powershell
# Windows: build stratac.exe, console.exe, libstrata.dll into compiler\bin\
powershell -ExecutionPolicy Bypass -File compiler\build.ps1
compiler\bin\stratac.exe run compiler\examples\run1.strata
# install to %LOCALAPPDATA%\Programs\strata and add to PATH
powershell -ExecutionPolicy Bypass -File compiler\install.ps1
```

```sh
# macOS / Linux: build stratac, console, libstrata.dylib / .so into compiler/bin/
sh compiler/build.sh
compiler/bin/stratac run compiler/examples/run1.strata
# install to ~/.local/share/strata, linked as ~/.local/bin/stratac
sh compiler/install.sh
```

```sh
# make a project
stratac new mygame
cd mygame
stratac run
```

`stratac` subcommands: `run`, `build`, `check`, `emit`, `ast`, `tokens`.

Tests (byte-for-byte golden files per compiler stage, projects, embedding):

```sh
powershell -ExecutionPolicy Bypass -File compiler\tests\run.ps1     # Windows
sh compiler/tests/run.sh                                            # macOS / Linux
```

## License

The Strata **compiler** is licensed under **GPL-3.0** ([`LICENSE`](LICENSE)) — modify it
and distribute your version, and you publish your source (the "Linux approach").

The Strata **runtime** carries a linking exception ([`LICENSE-RUNTIME.md`](LICENSE-RUNTIME.md)),
so **programs you build with Strata are entirely yours** — license and sell them under any
terms you like, open or closed. The GPL covers the compiler, never what you make with it.

The Strata **compiler library** (`libstrata`, for engines and tools) carries an embedding
exception ([`LICENSE-EMBEDDING.md`](LICENSE-EMBEDDING.md)): **any engine may embed Strata**,
whatever its license.

**Commercial license:** to modify the *compiler* and keep your changes private (no GPL
disclosure), a commercial license is available from **$100** — see [`COMMERCIAL.md`](COMMERCIAL.md).
Games built with Strata never need this.

**Strata™** — the name and branding are trademarks of the project author (common-law).
The code is GPL; the *name* is not — forks must use a different name. See
[`TRADEMARK.md`](TRADEMARK.md).

**Contributing:** by contributing you agree to the [CLA](CLA.md) — you keep your copyright,
and grant the project the right to use and relicense your contribution. See
[`CONTRIBUTING.md`](CONTRIBUTING.md).

Copyright © 2026 Connor Rutberg. Strata is free software under GPL-3.0; see [`LICENSE`](LICENSE).
