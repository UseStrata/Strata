/* Copyright © 2026 Connor Rutberg */
/* sarr.h - Strata's dynamic array runtime (`T[dynamic]`).
 *
 * A type-erased growable array: elements are stored inline by value. The compiler tracks
 * the element type, so indexing/push are type-checked in Strata; the runtime only needs
 * the element size. Grows geometrically via realloc.
 *
 * Buffers come from malloc/realloc and are not freed individually (arena philosophy: don't
 * free piecemeal; the OS reclaims at exit). Every buffer is linked into one list, so a
 * long-running host (e.g. an engine embedding the compiler) can free them all at once
 * with strata_arr_free_all(). An allocator-aware version comes later.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_SARR_H
#define STRATA_SARR_H

#include <sstate.h>

#include <stdlib.h>
#include <string.h>

typedef struct {
    void*     data;
    long long len;
    long long cap;
    long long elem;   /* element size in bytes */
} Array;

#define STRATA_ARR_TRACKED 1   /* this runtime can free all arrays (strata_arr_free_all) */

/* Each buffer is preceded by a list link (two pointers = 16 bytes, so data stays aligned). */
typedef struct StrataArrLink { struct StrataArrLink* prev; struct StrataArrLink* next; } StrataArrLink;
STRATA_STATE(StrataArrLink strata_arr_list, = { &strata_arr_list, &strata_arr_list });   /* circular, sentinel */

static inline void* strata_arr_realloc(void* data, size_t bytes) {
    StrataArrLink* h = data ? ((StrataArrLink*)data) - 1 : NULL;
    if (h) { h->prev->next = h->next; h->next->prev = h->prev; }     /* unlink (realloc may move it) */
    h = (StrataArrLink*)realloc(h, sizeof(StrataArrLink) + bytes);
    h->next = strata_arr_list.next; h->prev = &strata_arr_list;       /* link at the front */
    strata_arr_list.next->prev = h; strata_arr_list.next = h;
    return h + 1;
}

/* Free every array buffer. All arrays become invalid - only for hosts resetting everything. */
static inline void strata_arr_free_all(void) {
    StrataArrLink* h = strata_arr_list.next;
    while (h != &strata_arr_list) { StrataArrLink* n = h->next; free(h); h = n; }
    strata_arr_list.next = strata_arr_list.prev = &strata_arr_list;
}

static inline Array arr_make(long long elem) {
    Array a; a.data = 0; a.len = 0; a.cap = 0; a.elem = elem; return a;
}

static inline void arr_push(Array* a, const void* v) {
    if (a->len == a->cap) {
        long long nc = a->cap ? a->cap * 2 : 8;
        a->data = strata_arr_realloc(a->data, (size_t)(nc * a->elem));
        a->cap = nc;
    }
    memcpy((char*)a->data + a->len * a->elem, v, (size_t)a->elem);
    a->len += 1;
}

#endif /* STRATA_SARR_H */
