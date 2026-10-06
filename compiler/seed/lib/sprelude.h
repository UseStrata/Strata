/* Copyright © 2026 Connor Rutberg */
/* sprelude.h - Strata's built-in prelude: small math helpers always in scope.
 *
 * Just the conveniences C doesn't already give you cleanly (min/max collide with the
 * Windows macros, and clamp/lerp aren't standard). For sqrt/sin/cos, `import <math.h>`.
 * Prefixed sp_* so they never clash with C library symbols; the compiler maps the Strata
 * names (min, max, ...) to these.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_SPRELUDE_H
#define STRATA_SPRELUDE_H

static inline float sp_min(float a, float b) { return a < b ? a : b; }
static inline float sp_max(float a, float b) { return a > b ? a : b; }
static inline float sp_clamp(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
static inline float sp_lerp(float a, float b, float t) { return a + (b - a) * t; }
static inline float sp_abs(float x) { return x < 0.0f ? -x : x; }

#define SP_PI 3.14159265358979323846f

#endif /* STRATA_SPRELUDE_H */
