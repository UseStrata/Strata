# Strata Language Design (v0 draft)

> Status: **proposal to react to**, not settled. The syntax and rules here are a
> coherent, buildable starting point — anything can change. Decisions that still
> need your call are marked **[DECIDE]**.
>
> This is the *language* design (the "why" and the shape). User-facing how-to lives
> in [`../docs/`](../docs/). The founding plan and scope live in [`Strata.md`](../../Strata.md).

---

## 1. What Strata is (one paragraph)

A statically-typed, compiled language **for games and real-time software**, built on
four ideas: **arena/region memory** (no GC, no manual `free`), **first-class
data-oriented and math types**, **seamless C interop** (it compiles to C), and a
pluggable **hot-reload** runtime. The pitch it must always earn:

> *"Safer than C, simpler than Rust — the control C gives games, without the footguns
> or the borrow-checker fight."*

### 1.1 Static, not dynamic — deliberately
Strata is **statically typed**, and this is non-negotiable given the goals. Dynamic
typing forces runtime type tags + boxing, which forces a **GC or refcounting** — the
exact frame stutter Strata exists to remove — and can't lower to tight C. We get the
*lightness* of dynamic another way: **strong type inference** (§3), so you rarely
write a type except at function signatures and struct fields.

---

## 2. Feel of the language

Strata is designed to be **fast to learn, fast to write, fast to compile, fast to
run** — with the lowest learning curve we can manage for people coming from C#, C++,
C, or Godot. It reads C-family (types-first) so the biggest gamedev crowds read it on
sight, with modern conveniences layered on to cut ceremony.

- **Types-first declarations** (like C/C++/C#): `vec3 pos`, `Entity* e`.
- **`var` inference** for locals — write the type only where it aids clarity.
- **`for x in ...`** readable loops; **braces** for blocks (not whitespace-significant).
- **No semicolons** — a newline ends a statement.
- **Top-level code just runs** — no `void main() { }` wrapper needed for small programs.
- **Expression-bodied functions** — `= expr` for one-liners.
- **Default + named arguments** — self-documenting calls, no overload boilerplate.
- **First-class vector math** and **arena memory** as the headline sugar.

```strata
struct Entity {
    vec3 pos
    vec3 vel
    int  hp
}

vec3 update(Entity* e, float dt) {
    e.pos += e.vel * dt          // '.' auto-derefs
    return e.pos
}

// top-level code = the program's entry point (no boilerplate)
var world = arena()              // inferred, fully static
var e     = world.new(Entity)    // no malloc, no free
e.vel = vec3(1, 0, 0)

for i in 0..60 {
    update(e, 0.016)
}
// no free() — the arena reclaims in bulk
```

**Source files:** `.strata` is canonical; `.str` is an accepted short alias.

### 2.1 What we borrow, and from where (a disciplined mix, not a grab-bag)
One coherent spine (C-family, types-first), then proven *features* layered on:

| Borrow | From | Why it serves "easy + fast" |
|---|---|---|
| Low ceremony, tiny first program, `for x in` readability | **GDScript** | the low-learning-curve gold standard |
| Types-first syntax, braces, operators, compile-to-C, direct interop | **C / C++** | the incumbent every gamedev already reads |
| `var` type inference, value types, everyday readability | **C#** | the largest, most approachable gamedev crowd |
| Built-in dynamic arrays + maps, `for in` ranges, data-oriented types | **Odin** | modern conveniences without ceremony |
| Arena memory, hot-reload, fast-iteration mindset | **Jai** | performance + iteration philosophy |
| Tiny embeddable core | **Lua** | keep the language small on purpose |

---

## 3. Variables & constants

```strata
var x = 5           // inferred (int)
var speed = 4.5     // inferred (float)
vec3 pos            // declared, zero-initialized
string name = "hi"  // explicit type + value

const PI = 3.14159  // compile-time constant
```

- Everything is **zero-initialized** unless you opt out — no uninitialized reads.
- Inference (`var`) is the "feels dynamic, is static" ergonomic. Write explicit types
  at boundaries (fields, params, returns) where they document intent.
- `[DECIDE]` Shadowing in inner scopes? (Lean: yes, common in game loops.)

**Globals** (settled 2026-10-09): module-level state is declared with `global`, in any
file — including the main one, so its functions can share state:

```strata
global int score = 0
export global float volume = 0.8   // visible to files that import this one
global var name = "player"         // inferred
global vec3 spawn                  // zero-initialized
```

- Private to the file unless `export`ed, like every declaration.
- The initial value must be a constant (a number, char, bool, string or `null`); none
  means zero. A local of the same name hides the global.

---

## 4. Types

### 4.1 Primitives
`bool`, `int`, `float`, `string`, `byte`, plus sized forms `i8/i16/i32/i64`,
`u8/u16/u32/u64`, `f32/f64`.

- `[DECIDE]` Friendly-alias widths. Proposal: **`int` = `i64`**, **`float` = `f32`**
  (games default to 32-bit floats; 64-bit ints avoid surprise overflow). Sized types
  always available for control.

### 4.2 Math types (the differentiator — do early)
`vec2 vec3 vec4`, `mat2 mat3 mat4`, `quat`.

- Operators: `+ - *` (component-wise and scalar), `dot(a,b)`, `cross(a,b)`, `length`,
  `normalize`.
- **Swizzles:** `v.xy`, `v.xyz`, `v.zyx`, `v.rgba`.
- Construction: `vec3(1, 0, 0)`, `vec3(1)` (splat).
- Backed by the **existing math library** (asset in hand) — bind, don't rewrite.

### 4.3 Aggregates
```strata
struct Entity { vec3 pos; int hp }     // fields newline- or ';'-separated
enum State { Idle, Walk, Jump }
```

### 4.4 Pointers (inherited from D--'s model)
- `T*` a pointer, `&x` address-of, `*p` dereference.
- **`.` auto-dereferences** — write `e.pos`, never `(*e).pos`.

### 4.5 Arrays, slices, maps
```strata
int[64]   grid       // fixed-size array
int[]     view       // slice (ptr + len)
Entity[dynamic] mobs // dynamic array (arena-backed)   [DECIDE] syntax
Map<string,int> tbl  // built-in hash map              [DECIDE] syntax
```
- **SoA is opt-in** (Pillar 2.1), a later milestone: `#soa Entity[N]` gives
  struct-of-arrays layout. **Manual, never automatic** (honesty rule from the plan).
- `[DECIDE]` Array-type placement in a types-first world: `int[64] grid` (shown) vs
  `int grid[64]` (C-style). Lean: `int[64] grid` — the whole type reads left-to-right.

---

## 5. Memory: arenas & regions (the headline)

The rule anyone can learn in one sentence:

> **Everything in a region dies together; you never free individual objects.**

```strata
var world = arena()          // create a region
var e   = world.new(Entity)  // allocate in it (zeroed)
var buf = world.new(byte[1024])
// ...use freely...
world.reset()                // reclaim everything at once
```

Scoped form (auto-reclaims at block end):
```strata
region frame {
    var tmp = frame.new(byte[4096])
    // ...per-frame scratch...
}   // frame memory reclaimed here
```

- **v1:** plain arenas + scoped regions. No escape checking yet.
- **Stretch goal:** *region-enforced safety* — the checker refuses a pointer that
  would outlive its region. This is the "safer than C" headline if we land it.

---

## 6. Functions & control flow

```strata
int add(int a, int b) { return a + b }
void noret() { }                     // void = returns nothing

// expression-bodied form for one-liners (no braces, no `return`)
vec3  scale(vec3 v, float s) = v * s
float sq(float x) = x * x

// default + named arguments
void spawn(vec3 at, int hp = 100) { /* ... */ }
spawn(at: vec3(0), hp: 50)           // named args read self-documenting
spawn(vec3(0))                       // hp defaults to 100

if hp <= 0 { die() } else { live() }

for i in 0..count { }                // range (exclusive end)  [DECIDE] `..` vs `..<`
for e in entities { }                // iterate a slice/array
while running { }

switch state {                       // [DECIDE] switch vs match; fallthrough rules
    Idle: idle()
    Walk: walk()
}
```

- `[DECIDE]` Multiple return values? (`(vec3, bool) hit(...)`, used as
  `var v, ok = hit(...)`.) Lean: **yes** — big ergonomic win, cheap in C codegen via
  out-params.

---

## 7. Performance & iteration model (how it stays fast)

**Strata is compiled, not interpreted** — to C, then to native via tcc/gcc/clang.
Interpretation would add per-op dispatch overhead and force a GC, undoing the whole
point. But you get the *feel* of an interpreter from one command:

```bash
stratac run game.strata     # compiles (tcc, ~ms) and runs — feels like `python x.py`
stratac build game.strata   # release build via clang/gcc -O2
```

Because tcc compiles in milliseconds, `stratac run` gives an instant edit-run loop while
still producing native, no-GC code (same idea as `go run` / `zig run`). The milestone-5
**hot-reload** runtime is the "live-edit while running" story layered on top.

Three separate "fast" goals, each with concrete levers:

- **Fast to learn** — small keyword set, one obvious way to do each thing, familiar
  C-family control flow, top-level code with no boilerplate, a built-in **prelude**
  (math, input, time, arena) so the first playable program is ~15 lines, and *no
  lifetimes or borrow checker*.
- **Fast to compile** — lower to C, then use **tcc (Tiny C Compiler) for near-instant
  debug builds** and clang/gcc `-O2` for release. No header files; no heavy generics
  early; whole-module compile. Tight iteration loop is a first-class feature (Jai's
  main draw).
- **Fast to run** — no GC; arena memory (cache-friendly, bulk reclaim); value types by
  default; opt-in SoA; emit C so `-O2` gives decades of optimization for free.

---

## 8. C interoperability

Strata compiles to C, so calling C is direct. Consuming C *structs* and `#define`
constants needs real binding work (known friction, per the plan).

```strata
foreign "raylib.h" {                 // the C backend #includes the header
    struct Color { u8 r; u8 g; u8 b; u8 a }            // C's layout, passed by value
    const Color RAYWHITE = Color{ 245, 245, 245, 255 } // a macro's / enum constant's value
    void InitWindow(i32 w, i32 h, string title)        // C's int is i32
    void ClearBackground(Color color)
}
foreign {                            // no header: found when linking (e.g. a system DLL)
    u8* malloc(int size)
    i32 puts(string s)
}
```

- **Settled (2026-10-09): the `foreign` block**, not per-declaration `extern`. Each
  declaration says everything a backend needs to call the function, so the native backend
  calls C (raylib, the OS) without reading C headers; the C backend uses the header, or
  (none given) declares the functions itself. A foreign function keeps its exact name.
- `string` is a C `const char*`, so it converts to and from a pointer with `cast<T>`
  (e.g. a byte buffer `u8*`).
- **Structs and constants (2026-10-09):** a foreign `struct` keeps its exact C name and C's
  layout; a foreign `const` is a value (number, char, bool, string, null or a struct
  literal of them) that its uses are replaced by - on the C backend with a header, the
  header's struct and macro are used instead. Still to come: reading C headers
  automatically (declarations → a foreign block).
- **Link names (2026-10-10):** `u8* send_id(u8* obj, u8* sel) = "objc_msgSend"` declares
  a C function under another name - and so one C function under several signatures, which
  is how Objective-C's `objc_msgSend` must be called on ARM64 (each method's own C
  signature). The native backend calls the symbol; the C backend gives the prototype a
  GCC / Clang asm label. (CrossPlatform's macOS window is Cocoa this way.) Function
  pointers can come later, when callbacks need them.
- Free targets: **any C engine** (raylib, SDL, sokol, Box2D) and **Godot via
  GDExtension** (its C API). **Unreal needs a C++ shim** — stated honestly.

---

## 8b. Evaluation order

- **Settled (2026-10-09): left to right.** A call's arguments, a struct literal's fields
  and the two operands of a binary operator are evaluated left to right, on every backend
  (as in Go, Java, C#). `&&` / `||` evaluate their right side only when needed. C leaves
  argument order unspecified, so the C backend computes earlier operands into temporaries
  when a later one calls a function.

---

## 8c. `when`: compile-time conditions

- **Settled (2026-10-10): `when`** (the user's idea; the keyword as in Odin). Code for one
  target only, decided while compiling:
  ```strata
  when target_os == "windows" { import CrossPlatform.windows }
  else when target_os == "linux" { import CrossPlatform.linux }
  ```
  `target_os` / `target_arch` compared with strings, `&&` `||` `!`; at the top of a file and
  inside functions; `else when` / `else` chain. Only the chosen branch is compiled (the
  others are parsed, then dropped: their imports aren't loaded, their calls needn't exist).
  It replaces a hidden "load X/<os>.strata with X" rule: the dependency is written down.

---

## 9. Naming & style (proposal)

- `snake_case` functions/variables, `PascalCase` types, `SCREAMING_CASE` constants.
- One statement per line, no semicolons.

---

## 10. Open decisions (rolled up)

0. ~~Versioning scheme~~ — **settled: Semantic Versioning (Major.Minor.Patch).**
1. **Const syntax** confirm `const NAME = v`.
2. **Friendly-alias widths:** `int`=`i64`, `float`=`f32` — confirm.
3. **Dynamic array / map syntax:** `T[dynamic]` and `Map<K,V>`.
4. **Array-type placement:** `int[64] grid` vs C-style `int grid[64]`.
5. **Range operator:** `0..n` exclusive vs `0..<n`.
6. **Multiple return values:** yes/no (lean yes).
7. **switch vs match**, fallthrough behavior.
8. ~~**`foreign` block vs per-decl `extern`** for C interop.~~ **Settled: the `foreign` block** (§8).
9. **Region-enforced escape checking** — v1 stretch or explicitly post-v1.
10. **Shadowing** in inner scopes — allow?

> **Settled so far:** static typing (not dynamic); **compiled** (to C → native), with
> `stratac run` for an interpreter-like instant loop; types-first C-family spine with
> `var` inference; `.strata`/`.str` extensions; compile-to-C with tcc/`-O2`; arena +
> scoped regions as the memory headline; three syntax sugars — **top-level code = main**,
> **expression-bodied functions** (`= expr`), and **default + named arguments**.

---

## 11. Mapping to milestones (from the plan)

| Design area here | Roadmap step |
|---|---|
| §3–§4.1, §6 (core types, funcs, control flow), §5 (arenas) | 1. Compiler skeleton |
| §4.2 (vec/mat/quat) | 2. First-class math types |
| §8 (C interop) | 3. raylib bindings + demo |
| §4.5 SoA | 4. SoA / packed arrays |
| §7 hot-reload runtime | 5. Hot-reload library |
| §8 Godot | 6. GDExtension target |

---

## 12. Not yet designed (backlog)

Areas the design deliberately hasn't settled yet, grouped by how much they shape the
compiler. **★ = shapes the compiler skeleton / can't cleanly defer.**

**Data modeling (the biggest gaps for a game language)**
- ★ **Tagged unions / sum types + pattern matching** — `enum` that carries data, for
  state machines, events, ECS variants, `Option`/`Result`. We only have plain enums now.
- ★ **Methods on types + UFCS** — `e.update(dt)` vs `update(e, dt)`; decides call feel.
- ★ **Generics** — required for type-safe `T[dynamic]` and `Map<K,V>`; the design most
  in tension with "fast to compile."
- **Operator overloading** — built-in for math; do user types get it too?

**Semantics**
- ★ **Error handling** — signature-shaping. Options: `value, ok` returns / Zig-style
  error unions / `Result`+`Option`. Games avoid exceptions.
- **Strings** — UTF-8; length-prefixed vs null-terminated (C interop); ops.
- **Null / optionals** — is there `null`? nullable pointers? an `Option` type?
- **Numeric rules** — implicit vs explicit conversions; overflow behavior.
- **Bounds checking** — arrays/slices (debug-on / release-off?).
- **`defer`** — cleanup for non-memory resources (files, GPU handles).

**Ecosystem & organization**
- ★ **Modules / imports / visibility** — multi-file programs, `import`, public/private.
- **Project & build layout** — single-file vs manifest; dependency/package story.
- **Standard library / prelude scope** — math, IO, containers, input, time.

**Ambition knobs (take a stance now, build later)**
- **Compile-time execution / metaprogramming** — Jai-style `#run`. Lean: minimal for v1.
- **Concurrency / job system** — lean: post-v1.
- **Tooling** — formatter, LSP, debugger line-mapping (reuse C debuggers).
- **Testing** — built-in test support.

**Project decisions (from Strata.md)**
- **Versioning scheme** — element/atomic-number idea vs Strata-specific.
- **License** — MIT / Apache-2.0 / zlib (zlib popular in gamedev).

---

## 13. Compilation model — how Strata lowers to C

Strata **transpiles to plain C**, then a C compiler produces native code. It does **not**
compile like C++ and never touches a C++ compiler — going to C keeps the pipeline simple
and fast (this is what lets tcc do millisecond debug builds).

```
foo.strata → Strata compiler (in D--) → foo.c → tcc / gcc / clang → native
```

This mirrors the D-- pipeline, which already compiles to C successfully — so the approach
is proven, not speculative.

**Design rule: every language feature must lower to plain C.** All the ergonomic sugar is
compile-time-only — resolved in the checker, gone by the time C is emitted, zero runtime cost:

| Strata | Lowers to |
|---|---|
| `var x = 5` | `int64_t x = 5;` (type resolved in checker) |
| no semicolons | C's `;` reinserted by codegen |
| top-level code | collected into a generated `int main()` |
| `f(x) = expr` | `{ return expr; }` |
| default + named args | resolved at call site → positional C call |
| `e.pos` (auto-deref) | `e->pos` / `e.pos` as the type dictates |
| `for i in 0..n` | ordinary C `for` loop |
| `vec3 + vec3`, swizzles | `vec3_add(a,b)` / field reads (or C vector extensions) |
| arena / `region { }` | calls into the C arena runtime; scoped reset at block end |
| tagged union + `match` | C `struct { tag; union; }` + `switch` on tag |
| methods / UFCS | free function; `e.f(x)` → `f(e, x)` |

**Only real added compile work: generics** — via monomorphization (a specialized C
function/struct per concrete type used). Simpler than C++ templates because the compiler
controls which instantiations are generated; kept lean early per the "fast to compile" goal.
