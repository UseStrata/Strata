# seed/ — the C seed (bootstraps macOS and Linux)

The compiler is written in Strata, so building it needs a Strata compiler. On Windows,
`build.ps1` downloads the pinned release (`bootstrap.txt`). Releases are Windows
binaries, so macOS and Linux start from here instead:

| File | What |
|---|---|
| `stratac.c` | a `stratac` compiled to C (generated: never edit) |
| `src/strata_host.h`, `lib/*.h` | the headers it was generated against |
| `VERSION` | which `stratac` it is |

`build.sh` compiles `stratac.c` with `cc` into stage0 (with its own copy of `lib/`), then
does the usual stage1 → stage2 bootstrap with the fixpoint check. The headers are kept
here so the seed keeps compiling however `src/` and `lib/` change later.

**The seed rule** (the same as `bootstrap.txt`'s): `src/` may only use language features
the seed's compiler supports. Refresh the seed when releasing, and before `src/` starts
using a new feature.

## Making / refreshing it

Any machine with a working `stratac` for the current sources:

```
powershell -ExecutionPolicy Bypass -File compiler\build.ps1 -WriteSeed     # Windows
sh compiler/build.sh --write-seed                                          # macOS / Linux
```

Then commit `compiler/seed/`. The generated C is the same on every platform (it is the
fixpoint of the compiler building itself; platform differences live in the headers,
behind `#ifdef`s), so a seed made on one OS bootstraps all of them.

The first seed has to come from Windows: it must be a compiler with the cross-platform
host layer (1.6.0+), and only the Windows releases can build one.
