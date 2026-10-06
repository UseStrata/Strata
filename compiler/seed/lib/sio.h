/* Copyright © 2026 Connor Rutberg */
/* sio.h - Strata's process I/O runtime: read_file / write_file / args.
 *
 * read_file(path) returns the whole file as a string ("" if it can't be opened);
 * write_file(path, data) replaces the file and returns whether it fully succeeded.
 * Binary mode, so bytes round-trip exactly. Buffers live in the string arena.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_SIO_H
#define STRATA_SIO_H

#include <sstate.h>

#include <stdio.h>
#include <stdbool.h>
#include <sstr.h>
#include <sarr.h>

/* args(): the command-line arguments as a string[dynamic] (args()[0] = the program).
 * The generated main() records argc/argv here before any user code runs. */
STRATA_STATE(int    strata_argc_v, );
STRATA_STATE(char** strata_argv_v, );
static inline void strata_set_args(int argc, char** argv) { strata_argc_v = argc; strata_argv_v = argv; }
static inline Array strata_args(void) {
    Array a = arr_make(sizeof(const char*));
    for (int i = 0; i < strata_argc_v; i++) { const char* s = strata_argv_v[i]; arr_push(&a, &s); }
    return a;
}

static inline const char* strata_read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) return "";
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return ""; }
    char* buf = (char*)arena_alloc(strata_str_arena(), (size_t)sz + 1);
    size_t got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[got] = '\0';
    strata_len_put(buf, got);
    return buf;
}

static inline bool strata_write_file(const char* path, const char* data) {
    FILE* f = fopen(path, "wb");
    if (!f) return false;
    size_t len = strata_strlen(data);
    size_t wrote = len ? fwrite(data, 1, len, f) : 0;
    fclose(f);
    return wrote == len;
}

#endif /* STRATA_SIO_H */
