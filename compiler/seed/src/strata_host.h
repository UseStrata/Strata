/* SPDX-License-Identifier: GPL-3.0-only */
/* Copyright © 2026 Connor Rutberg */
/* src/strata_host.h - the compiler's link to whatever is hosting it.
 *
 * The compiler is written in Strata, but a few things it needs are plain process state,
 * which Strata (no global variables) keeps here in C. Compiler modules
 * `import "strata_host.h"`:
 *
 *   strata_report(msg)     every message for the user (errors, "built ...") goes through
 *                          this: printed by the CLI, captured into a buffer when a host
 *                          (an engine, via libstrata) asks for it
 *   strata_host_reset()    free everything the compiler allocated (strings, boxed values,
 *                          arrays), so an engine can compile over and over without growing
 *   strata_host_libdir()   the runtime lib/ folder: set by the host, or found next to
 *                          libstrata (.dll / .so / .dylib)
 *   strata_host_os() ...   everything that differs between operating systems (paths,
 *                          folders, starting gcc), through lib/crossplatform.h
 *
 * It sits beside the compiler's sources (not in lib/) so the pinned bootstrap release can
 * still compile the compiler. */
#ifndef STRATA_HOST_H
#define STRATA_HOST_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arena.h>
#include <sstr.h>
#include <sarr.h>

/* The platform layer, from THIS repo's lib/ (a path relative to this file): the pinned
 * bootstrap release compiles the compiler against its own, older lib/, whose
 * crossplatform.h has only the Window section. Private to the compiler (static), and
 * without the Window section (no <windows.h> in the compiler's C). */
#define STRATA_CROSSPLATFORM
#define STRATA_CROSSPLATFORM_STATIC
#define STRATA_CROSSPLATFORM_NO_WINDOW
#include "../lib/crossplatform.h"

/* ---- messages ------------------------------------------------------------- */

static char*  strata_host_buf = NULL;
static size_t strata_host_len = 0;
static size_t strata_host_cap = 0;
static int    strata_host_capturing = 0;

static inline void strata_report(const char* msg) {
    if (!strata_host_capturing) { puts(msg); return; }
    size_t n = strlen(msg);
    if (strata_host_len + n + 2 > strata_host_cap) {
        size_t cap = strata_host_cap ? strata_host_cap : 256;
        while (strata_host_len + n + 2 > cap) cap *= 2;
        strata_host_buf = (char*)realloc(strata_host_buf, cap);
        strata_host_cap = cap;
    }
    memcpy(strata_host_buf + strata_host_len, msg, n);
    strata_host_len += n;
    strata_host_buf[strata_host_len++] = '\n';
    strata_host_buf[strata_host_len] = '\0';
}

/* Start capturing messages (clears the previous capture). */
static inline void strata_capture_begin(void) {
    strata_host_capturing = 1;
    strata_host_len = 0;
    if (strata_host_buf) strata_host_buf[0] = '\0';
}
static inline void strata_capture_end(void) { strata_host_capturing = 0; }
/* The captured messages, one per line ("" if none). Survives strata_host_reset(). */
static inline const char* strata_capture_text(void) { return strata_host_buf ? strata_host_buf : ""; }

/* ---- joining strings -------------------------------------------------------- */

/* Concatenate a string[dynamic] in one pass: measure every piece, allocate once, copy
 * once. (In Strata, joining n pieces with `+` copies the growing result each time.) */
static inline const char* strata_join(const Array* parts) {
    const char** p = (const char**)parts->data;
    size_t total = 0;
    for (long long i = 0; i < parts->len; i++) total += strlen(p[i]);
    char* r = (char*)arena_alloc(strata_str_arena(), total + 1);
    size_t at = 0;
    for (long long i = 0; i < parts->len; i++) {
        size_t n = strlen(p[i]);
        memcpy(r + at, p[i], n);
        at += n;
    }
    r[total] = '\0';
#ifdef STRATA_STR_LEN_CACHE
    strata_len_put(r, total);
#endif
    return r;
}

/* ---- the operating system ---------------------------------------------------- */

/* "windows", "macos" or "linux" */
static inline const char* strata_host_os(void) { return PlatformName(); }

/* The C compiler builds run: $STRATA_CC if set (one program name or path, e.g. "clang"),
 * else gcc on Windows (MinGW) and cc elsewhere (gcc or clang). */
static inline const char* strata_cc(void) {
    const char* cc = getenv("STRATA_CC");
    if (cc && cc[0]) return cc;
#ifdef _WIN32
    return "gcc";
#else
    return "cc";
#endif
}

/* The running executable's path ("" if unknown). */
static inline const char* strata_exe_path(void) {
    static char buf[4096];
    if (!PlatformExecutablePath(buf, sizeof buf)) buf[0] = '\0';
    return buf;
}

/* ---- files ------------------------------------------------------------------ */

static inline bool strata_file_exists(const char* path) { return PlatformPathExists(path) != 0; }

/* Create a folder and its missing parents; true if it exists afterwards. */
static inline bool strata_make_dirs(const char* path) { return PlatformMakeDirectories(path) != 0; }

/* ---- running programs --------------------------------------------------------- */

/* How many programs to run at once: the machine's core count. */
static inline long long strata_cpu_count(void) { return PlatformCpuCount(); }

/* "error: could not start 'gcc' ..." (reported, like every message) */
static inline void strata_report_no_start(const char* program) {
    char msg[1200];
    if (strcmp(program, strata_cc()) == 0)
        snprintf(msg, sizeof msg, "error: could not start the C compiler '%s' (is it installed and on PATH? STRATA_CC picks another)", program);
    else
        snprintf(msg, sizeof msg, "error: could not start '%s'", program);
    strata_report(msg);
}

/* Run a program (a string[dynamic]: the program, then its arguments; no shell, so
 * nothing needs quoting) and wait for it. Returns its exit code, -1 if it couldn't start
 * (and says so). */
static inline long long strata_run_argv(const Array* argv) {
    if (argv->len < 1) return -1;
    const char** a = (const char**)malloc(sizeof(const char*) * (size_t)(argv->len + 1));
    if (!a) return -1;
    memcpy(a, argv->data, sizeof(const char*) * (size_t)argv->len);
    a[argv->len] = NULL;
    PlatformProcess p = PlatformStartProcess(a);
    int rc = p ? PlatformWaitProcess(p) : -1;
    if (!p) strata_report_no_start(a[0]);
    free(a);
    return rc;
}

/* Run `<cc> @file` for each response file, up to `jobs` at a time (started directly: no
 * shell in between, which on Windows costs real time per process). Returns how many
 * failed. */
static inline long long strata_run_cc_parallel(const Array* rsp_files, long long jobs) {
    const char** f = (const char**)rsp_files->data;
    long long n = rsp_files->len, failed = 0, waited = 0;
    int reported = 0;
    if (jobs < 1) jobs = 1;
    PlatformProcess* p = (PlatformProcess*)malloc(sizeof(PlatformProcess) * (size_t)(n ? n : 1));
    char** args = (char**)malloc(sizeof(char*) * (size_t)(n ? n : 1));
    if (!p || !args) { free(p); free(args); return n ? n : 1; }
    for (long long i = 0; i < n; i++) {
        while (i - waited >= jobs) {                   /* window full: wait for the oldest */
            if (!p[waited] || PlatformWaitProcess(p[waited]) != 0) failed++;
            waited++;
        }
        size_t len = strlen(f[i]);
        args[i] = (char*)malloc(len + 2);
        if (args[i]) { args[i][0] = '@'; memcpy(args[i] + 1, f[i], len + 1); }
        const char* argv[3] = { strata_cc(), args[i], NULL };
        p[i] = args[i] ? PlatformStartProcess(argv) : 0;
        if (!p[i] && !reported) { strata_report_no_start(strata_cc()); reported = 1; }
    }
    for (; waited < n; waited++) {
        if (!p[waited] || PlatformWaitProcess(p[waited]) != 0) failed++;
    }
    for (long long i = 0; i < n; i++) free(args[i]);
    free(args);
    free(p);
    return failed;
}

/* ---- memory --------------------------------------------------------------- */

/* Free one dynamic array's buffer now (e.g. a module's tokens once it's parsed) and leave
 * it empty. Only for arrays nothing else still points into. */
static inline void strata_array_free(Array* a) {
#ifdef STRATA_ARR_TRACKED
    if (a->data) {
        StrataArrLink* h = ((StrataArrLink*)a->data) - 1;
        h->prev->next = h->next;
        h->next->prev = h->prev;
        free(h);
    }
#else
    free(a->data);           /* older runtimes: a plain malloc'd buffer */
#endif
    a->data = 0; a->len = 0; a->cap = 0;
}

static inline void strata_host_reset(void) {
#ifdef STRATA_STR_LEN_CACHE   /* frees the strings and forgets their remembered lengths */
    strata_str_reset();
#else
    arena_free(strata_str_arena());
#endif
    arena_free(strata_heap());
#ifdef STRATA_ARR_TRACKED   /* older runtimes (e.g. the bootstrap release's) can't free arrays */
    strata_arr_free_all();
#endif
}

/* ---- the runtime lib/ folder ------------------------------------------------ */

static char strata_host_libdir_buf[1024];

static inline void strata_host_set_libdir(const char* dir) {
    snprintf(strata_host_libdir_buf, sizeof strata_host_libdir_buf, "%s", dir ? dir : "");
}

static inline int strata_host_is_libdir(const char* dir) {
    char probe[1100];
    snprintf(probe, sizeof probe, "%s/arena.h", dir);
    return PlatformPathExists(probe);
}

/* The host's choice; else lib/ next to the module containing this code (for libstrata:
 * the install folder), or one level up (the repo layout: bin/../lib); else "lib". */
static inline const char* strata_host_libdir(void) {
    if (strata_host_libdir_buf[0]) return strata_host_libdir_buf;
    char path[1024];
    if (PlatformModulePath((const void*)&strata_host_libdir, path, sizeof path)) {
        char* slash = strrchr(path, '/');
#ifdef _WIN32
        char* bslash = strrchr(path, '\\');
        if (!slash || (bslash && bslash > slash)) slash = bslash;
#endif
        if (slash) {
            *slash = '\0';
            snprintf(strata_host_libdir_buf, sizeof strata_host_libdir_buf, "%s/lib", path);
            if (strata_host_is_libdir(strata_host_libdir_buf)) return strata_host_libdir_buf;
            snprintf(strata_host_libdir_buf, sizeof strata_host_libdir_buf, "%s/../lib", path);
            if (strata_host_is_libdir(strata_host_libdir_buf)) return strata_host_libdir_buf;
            strata_host_libdir_buf[0] = '\0';
        }
    }
    return "lib";
}

#endif /* STRATA_HOST_H */
