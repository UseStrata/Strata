/* Copyright © 2026 Connor Rutberg */
/* sstr.h - Strata's string runtime.
 *
 * Strata's `string` lowers to C `const char*` (so it passes to C libraries with no
 * conversion). This header adds the operations the language exposes on strings:
 * concatenation, length, and equality. Concatenation allocates in a lazily-created
 * global string arena, so results are never freed individually (the arena discipline).
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_SSTR_H
#define STRATA_SSTR_H

#include <sstate.h>

#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <arena.h>

STRATA_STATE(Arena strata_str_arena_v, );
STRATA_STATE(int   strata_str_arena_ready, = 0);
static inline Arena* strata_str_arena(void) {
    if (!strata_str_arena_ready) { strata_str_arena_v = arena_make(); strata_str_arena_ready = 1; }
    return &strata_str_arena_v;
}

/* ---- remembered lengths --------------------------------------------------------
 * A Strata string is a plain C string, so its length means a strlen scan. For LONG strings
 * the runtime created (concatenation, substr, read_file) it remembers the length in a
 * small hash table keyed by the pointer, making .len, substr and + on them O(1) in the
 * string's size. That is what keeps e.g. a lexer walking a 1 MB source file linear.
 * It is safe because these strings are immutable and their memory is only reused after
 * strata_str_reset(), which forgets them all; any other string (a C literal, a buffer from
 * C code) is simply measured with strlen. */
#define STRATA_STR_LEN_CACHE 1
#define STRATA_LEN_MIN 128            /* shorter strings are cheap to measure */

typedef struct { const char* p; size_t len; } StrataLen;
STRATA_STATE(StrataLen* strata_len_tab, = NULL);
STRATA_STATE(size_t     strata_len_cap, = 0);     /* power of two */
STRATA_STATE(size_t     strata_len_count, = 0);

static inline size_t strata_len_slot(const char* p, size_t cap) {
    unsigned long long x = (unsigned long long)(uintptr_t)p;
    x ^= x >> 29; x *= 0xBF58476D1CE4E5B9ull; x ^= x >> 32;
    return (size_t)(x & (cap - 1));
}

static inline void strata_len_put(const char* p, size_t len) {
    if (len < STRATA_LEN_MIN) return;
    if ((strata_len_count + 1) * 2 > strata_len_cap) {          /* keep load <= 1/2 */
        size_t ncap = strata_len_cap ? strata_len_cap * 2 : 1024;
        StrataLen* nt = (StrataLen*)calloc(ncap, sizeof(StrataLen));
        if (!nt) return;                                           /* no memory: just don't remember */
        for (size_t i = 0; i < strata_len_cap; i++) {
            if (strata_len_tab[i].p) {
                size_t j = strata_len_slot(strata_len_tab[i].p, ncap);
                while (nt[j].p) j = (j + 1) & (ncap - 1);
                nt[j] = strata_len_tab[i];
            }
        }
        free(strata_len_tab);
        strata_len_tab = nt; strata_len_cap = ncap;
    }
    size_t j = strata_len_slot(p, strata_len_cap);
    while (strata_len_tab[j].p && strata_len_tab[j].p != p) j = (j + 1) & (strata_len_cap - 1);
    if (!strata_len_tab[j].p) strata_len_count++;
    strata_len_tab[j].p = p;
    strata_len_tab[j].len = len;
}

/* strlen, unless the runtime remembers this string's length */
static inline size_t strata_strlen(const char* p) {
    if (strata_len_cap) {
        size_t j = strata_len_slot(p, strata_len_cap);
        while (strata_len_tab[j].p) {
            if (strata_len_tab[j].p == p) return strata_len_tab[j].len;
            j = (j + 1) & (strata_len_cap - 1);
        }
    }
    return strlen(p);
}

/* Free every runtime string and forget their lengths (hosts resetting the compiler). */
static inline void strata_str_reset(void) {
    arena_free(strata_str_arena());
    if (strata_len_tab) memset(strata_len_tab, 0, strata_len_cap * sizeof(StrataLen));
    strata_len_count = 0;
}

/* ---- the string operations ---------------------------------------------------------- */

static inline const char* str_concat(const char* x, const char* y) {
    size_t lx = strata_strlen(x), ly = strata_strlen(y);
    char* r = (char*)arena_alloc(strata_str_arena(), lx + ly + 1);
    memcpy(r, x, lx); memcpy(r + lx, y, ly); r[lx + ly] = '\0';
    strata_len_put(r, lx + ly);
    return r;
}
static inline int      str_eq(const char* x, const char* y) { return strcmp(x, y) == 0; }
static inline long long str_len(const char* x) { return (long long)strata_strlen(x); }

/* substr(s, start, n): n bytes from `start`, clamped to the string's bounds. */
static inline const char* str_sub(const char* s, long long start, long long n) {
    long long len = (long long)strata_strlen(s);
    if (start < 0) start = 0;
    if (start > len) start = len;
    if (n < 0) n = 0;
    if (start + n > len) n = len - start;
    char* r = (char*)arena_alloc(strata_str_arena(), (size_t)n + 1);
    memcpy(r, s + start, (size_t)n); r[n] = '\0';
    strata_len_put(r, (size_t)n);
    return r;
}

/* int_to_str(n): decimal text of an integer. */
static inline const char* str_from_int(long long v) {
    char tmp[32];
    int n = snprintf(tmp, sizeof tmp, "%lld", v);
    char* r = (char*)arena_alloc(strata_str_arena(), (size_t)n + 1);
    memcpy(r, tmp, (size_t)n + 1);
    return r;
}

#endif /* STRATA_SSTR_H */
