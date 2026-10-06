/* Copyright © 2026 Connor Rutberg */
/* sstate.h - how the Strata runtime declares its process-wide state.
 *
 * A Strata program is normally compiled as ONE C file, and the runtime's state (arenas,
 * the remembered string lengths, args(), ...) is simply `static`. A project build may
 * instead compile one C file per module (STRATA_SPLIT, so only changed modules recompile).
 * Then the state must exist once: the main module's file (STRATA_MAIN_TU) defines it and
 * the other files refer to it.
 *
 *     STRATA_STATE(int strata_heap_ready, = 0);
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_SSTATE_H
#define STRATA_SSTATE_H

#if defined(STRATA_SPLIT) && !defined(STRATA_MAIN_TU)
#define STRATA_STATE(decl, ...) extern decl
#elif defined(STRATA_SPLIT)
#define STRATA_STATE(decl, ...) decl __VA_ARGS__
#else
#define STRATA_STATE(decl, ...) static decl __VA_ARGS__
#endif

#endif /* STRATA_SSTATE_H */
