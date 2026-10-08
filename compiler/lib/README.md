# Strata runtime (`lib/`)

The **runtime** that *compiled programs* use — not code the compiler itself runs. It is
installed beside `stratac` (`<install>/lib/`), which finds it there.

| File | Provides |
|---|---|
| `arena.h` | arenas / regions (zero-GC memory) and the global heap behind `alloc` |
| `sstr.h` | strings: concatenation, equality, length, `substr`, `int_to_str` |
| `sarr.h` | dynamic arrays (`T[dynamic]`) |
| `sio.h` | `read_file`, `write_file`, `args()` |
| `smath.h` | `vec2/3/4`, `mat4`, `quat` and their operations |
| `sprelude.h` | `min`, `max`, `clamp`, `lerp`, `PI` |
| `sstate.h` | how runtime state is declared (one C file, or shared by a split build) |
| `crossplatform.h` | a single-header platform layer (Window, System, Files, Process) |
| `srt.c` | the entry points (`srt_*`) that natively compiled programs call into |
| `srt.o` | `srt.c` compiled (by `build.ps1`; not in git) — what Strata's linker links |

The **C backend** passes `-I <install>/lib` so generated C can `#include` the headers.
The **native backend** (Strata's own x86-64 code) calls the `srt_*` functions in `srt.c`,
which wrap the same headers, so both backends behave alike. Strata's linker links the
prebuilt `srt.o`, so native builds need no C compiler; `srt.c` may therefore only call
what Windows' `msvcrt.dll` exports. It is the next piece to be written in Strata itself.

License: GPL-3.0 with the runtime linking exception (`../../LICENSE-RUNTIME.md`):
programs built with Strata are not covered by the GPL.
