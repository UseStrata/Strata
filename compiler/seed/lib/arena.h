/* Copyright © 2026 Connor Rutberg */
/* arena.h - Strata's arena/region allocator: the zero-GC memory runtime.
 *
 * The rule the language exposes: everything in a region dies together; you never free
 * individual objects. This is the C the compiler emits calls into.
 *
 * Chunked (a linked list of blocks) so that pointers into the arena stay valid as it
 * grows - a block, once allocated, never moves. Header-only; `static inline`, so
 * including it where a function is unused produces no warnings.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_ARENA_H
#define STRATA_ARENA_H

#include <sstate.h>

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef struct StrataBlock {
    struct StrataBlock* next;
    size_t used;
    size_t cap;
    /* the block's bytes follow this header in the same allocation */
} StrataBlock;

typedef struct {
    StrataBlock* head;   /* current block (newest); blocks are singly linked */
} Arena;

#define STRATA_ARENA_MIN ((size_t)1 << 16)   /* 64 KB minimum block */

static inline StrataBlock* strata_block_new(size_t need) {
    size_t cap = STRATA_ARENA_MIN;
    while (cap < need) { cap *= 2; }
    StrataBlock* b = (StrataBlock*)malloc(sizeof(StrataBlock) + cap);
    b->next = NULL;
    b->used = 0;
    b->cap  = cap;
    return b;
}

static inline Arena arena_make(void) {
    Arena a;
    a.head = NULL;
    return a;
}

/* Allocate `size` bytes (16-byte aligned), zeroed. The returned pointer is stable for
 * the life of the arena - growing the arena never moves existing allocations. */
static inline void* arena_alloc(Arena* a, size_t size) {
    size_t sz = (size + 15u) & ~((size_t)15u);
    if (a->head == NULL || a->head->used + sz > a->head->cap) {
        StrataBlock* b = strata_block_new(sz);
        b->next = a->head;
        a->head = b;
    }
    unsigned char* data = (unsigned char*)(a->head + 1);
    void* p = data + a->head->used;
    a->head->used += sz;
    memset(p, 0, size);
    return p;
}

/* Reclaim everything in the arena at once (the whole region dies together). */
static inline void arena_free(Arena* a) {
    StrataBlock* b = a->head;
    while (b != NULL) { StrataBlock* n = b->next; free(b); b = n; }
    a->head = NULL;
}

/* A process-global heap backing `alloc(value)` (boxed values; reclaimed at exit). */
STRATA_STATE(Arena strata_heap_v, );
STRATA_STATE(int   strata_heap_ready, = 0);
static inline Arena* strata_heap(void) {
    if (!strata_heap_ready) { strata_heap_v = arena_make(); strata_heap_ready = 1; }
    return &strata_heap_v;
}

#endif /* STRATA_ARENA_H */
