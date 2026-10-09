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
| `srt.strata` | the runtime of natively compiled programs (`srt_*`), **written in Strata** |
| `srt.o` | `srt.strata` compiled by `stratac object` (`build.ps1`; not in git) — what native programs link |

The **C backend** passes `-I <install>/lib` so generated C can `#include` the headers.
The **native backend** (Strata's own x86-64 code) calls the `srt_*` functions of
`srt.strata`, which behave exactly like the C headers do, so both backends print the same.
It is plain Strata: the few things it needs from Windows (memory, files, `puts`,
`sinf` / `cosf` / `tanf` from msvcrt.dll) are in its `foreign` block, and its state is in
`global` variables. Strata compiles it into `srt.o` with its own native backend.

License: GPL-3.0 with the runtime linking exception (`../../LICENSE-RUNTIME.md`):
programs built with Strata are not covered by the GPL.
