/* strata.h - embed the Strata compiler (libstrata) in an engine, editor or tool.
 * Copyright © 2026 Connor Rutberg. Strata is GPL-3.0 with the Strata Embedding Exception:
 * any program may link and ship libstrata, whatever its own license (LICENSE-EMBEDDING.md).
 *
 * Link:   gcc/clang (MinGW)  host.c -I<strata>/include -L<strata> -lstrata
 *         macOS / Linux      cc host.c -I<strata>/include -L<strata> -lstrata -Wl,-rpath,<strata>
 *                            (libstrata.dylib / libstrata.so; found through the rpath)
 *         anything else      load the library at runtime (LoadLibrary / dlopen, P/Invoke, ...)
 * Ship:   libstrata (.dll / .dylib / .so), and the lib/ folder beside it (Strata's runtime
 *         headers, needed to build programs). strata_build() also needs a C compiler on
 *         PATH: gcc on Windows, cc elsewhere, or $STRATA_CC.
 *
 * Conventions
 *   - Strings are UTF-8 and NUL-terminated. Strings returned by the library stay valid
 *     until strata_reset().
 *   - Messages (errors, "built ...") are captured, not printed: after any call, read them
 *     with strata_diagnostics(). Error lines look like "file.strata:12:5: error: ...".
 *   - Not thread-safe: call it from one thread at a time.
 *   - Paths may use / or \. A "program" is a root .strata file plus the modules it imports
 *     (resolved from the root file's folder).
 *
 * Example
 *     if (!strata_check("game/main.strata")) fputs(strata_diagnostics(), stderr);
 *     if (strata_build("game", false, false)) load_library(strata_output_path("game"));
 *     strata_reset();   // after you're done with the returned strings
 */
#ifndef STRATA_H
#define STRATA_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) && !defined(STRATA_STATIC)
#define STRATA_API __declspec(dllimport)
#else
#define STRATA_API
#endif

/* The compiler version, e.g. "1.3.0 (embedding)". */
STRATA_API const char* strata_version(void);

/* ---- checking (fast; no C compiler needed) ---------------------------------------- */

/* Type-check the program rooted at `path`. True if it has no errors. */
STRATA_API bool strata_check(const char* path);

/* Same, but the root file's text is `source` (e.g. an unsaved editor buffer); the modules
 * it imports are still read from disk, relative to `path`'s folder. */
STRATA_API bool strata_check_source(const char* path, const char* source);

/* ---- compiling to C (no C compiler needed) ---------------------------------------- */

/* The program rooted at `path`, compiled to C. Returns "" on errors (see diagnostics).
 * To compile the C yourself, add Strata's lib/ folder to the include path. */
STRATA_API const char* strata_emit(const char* path);
STRATA_API const char* strata_emit_source(const char* path, const char* source);

/* ---- building (uses gcc) ------------------------------------------------------------ */

/* Build `target` into an exe or dll. `target` is a .strata file, a project folder, or a
 * strata.toml. Projects are cached: an unchanged project skips the C compiler.
 * release: optimize (-O2). force: rebuild even if cached. True on success. */
STRATA_API bool strata_build(const char* target, bool release, bool force);

/* Where strata_build(target, ...) writes its exe or dll ("" if the target isn't valid). */
STRATA_API const char* strata_output_path(const char* target);

/* ---- housekeeping --------------------------------------------------------------------- */

/* Messages from the most recent call, one per line ("" if there were none). */
STRATA_API const char* strata_diagnostics(void);

/* Where Strata's runtime headers (lib/) are. Default: the lib/ folder next to
 * libstrata.dll, as installed. */
STRATA_API void strata_set_libdir(const char* dir);

/* Free all memory the compiler has allocated. Every string it returned becomes invalid. */
STRATA_API void strata_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* STRATA_H */
