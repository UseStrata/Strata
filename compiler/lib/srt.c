/* Copyright © 2026 Connor Rutberg */
/* srt.c - the runtime entry points for programs compiled by Strata's NATIVE backend.
 *
 * Natively compiled code (src/lower.strata, src/x64.strata) does its own arithmetic,
 * control flow and vector math, and calls these `srt_*` functions for the rest: printing,
 * arenas, strings, dynamic arrays, files, matrices and quaternions. They wrap the same
 * header-only runtime the C backend uses, so both backends behave alike.
 *
 * Structs travel by pointer (results through the first argument), so no struct-passing
 * rules are involved.
 *
 * It is compiled ahead of time (build.ps1 -> lib/srt.o) and linked by Strata's own linker
 * (src/pelink.strata), which resolves what it calls straight from the C runtime that ships
 * with Windows (msvcrt.dll). So it must only call functions msvcrt.dll exports - no
 * MinGW-only helpers: numbers are formatted here, not with snprintf, and the build keeps
 * gcc from merging sinf + cosf into sincosf. (With no srt.o, the C toolchain links srt.c.)
 * It is the next piece to be rewritten in Strata itself.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#define __USE_MINGW_ANSI_STDIO 0   /* printf & co. straight from msvcrt.dll */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <arena.h>
#include <smath.h>
#include <sstr.h>
#include <sio.h>
#include <sarr.h>

void srt_set_args(int argc, char** argv) { strata_set_args(argc, argv); }

/* ---- number formatting (no snprintf: see above) ------------------------------------ */

/* v in decimal into buf (at least 24 bytes); returns the length */
static int srt_fmt_int(char* buf, long long v) {
    char tmp[24];
    int n = 0, len = 0;
    unsigned long long u = v < 0 ? 0ull - (unsigned long long)v : (unsigned long long)v;
    do { tmp[n++] = (char)('0' + (int)(u % 10)); u /= 10; } while (u);
    if (v < 0) buf[len++] = '-';
    while (n) buf[len++] = tmp[--n];
    buf[len] = '\0';
    return len;
}

/* v as printf's "%g" writes it (6 significant digits, the shorter of fixed and
 * exponent notation, trailing zeros dropped, a 2-digit exponent at least). The digits
 * come from msvcrt's "%.5e", which rounds correctly; the layout is done here, because
 * msvcrt's own %g writes 3-digit exponents ("1e+006") and spells inf / nan differently. */
static void srt_fmt_g(char* out, double v) {
    if (v != v) { strcpy(out, "nan"); return; }
    uint64_t bits;
    memcpy(&bits, &v, 8);
    int neg = (int)(bits >> 63);
    char* o = out;
    if (neg) { *o++ = '-'; v = -v; }
    if (v - v != 0) { strcpy(o, "inf"); return; }
    if (v == 0) { strcpy(o, "0"); return; }
    char e[64];
    _snprintf(e, sizeof e, "%.5e", v);         /* d.ddddde+XXX */
    e[sizeof e - 1] = '\0';
    char dig[7];
    dig[0] = e[0];
    for (int i = 0; i < 5; i++) dig[i + 1] = e[2 + i];
    dig[6] = '\0';
    const char* ep = strchr(e, 'e');
    int x = ep ? atoi(ep + 1) : 0;
    int nd = 6;
    while (nd > 1 && dig[nd - 1] == '0') nd--;  /* significant digits that remain */
    if (x < -4 || x >= 6) {
        *o++ = dig[0];
        if (nd > 1) { *o++ = '.'; for (int i = 1; i < nd; i++) *o++ = dig[i]; }
        *o++ = 'e';
        *o++ = x < 0 ? '-' : '+';
        int ax = x < 0 ? -x : x;
        if (ax < 10) *o++ = '0';
        o += srt_fmt_int(o, ax);
        *o = '\0';
    } else if (x >= 0) {
        for (int i = 0; i <= x; i++) *o++ = i < nd ? dig[i] : '0';
        if (nd > x + 1) { *o++ = '.'; for (int i = x + 1; i < nd; i++) *o++ = dig[i]; }
        *o = '\0';
    } else {
        *o++ = '0'; *o++ = '.';
        for (int i = 0; i < -x - 1; i++) *o++ = '0';
        for (int i = 0; i < nd; i++) *o++ = dig[i];
        *o = '\0';
    }
}

void srt_print_i64(long long v)    { char b[24]; srt_fmt_int(b, v); puts(b); }
void srt_print_f64(double v)       { char b[64]; srt_fmt_g(b, v); puts(b); }
void srt_print_str(const char* s)  { puts(s); }

void* srt_arena_alloc(Arena* a, long long size) { return arena_alloc(a, (size_t)size); }
void  srt_arena_free(Arena* a)                  { arena_free(a); }
void* srt_heap_alloc(long long size)            { return arena_alloc(strata_heap(), (size_t)size); }

const char* srt_str_concat(const char* a, const char* b)          { return str_concat(a, b); }
int         srt_str_eq(const char* a, const char* b)              { return str_eq(a, b); }
long long   srt_str_len(const char* s)                            { return str_len(s); }
const char* srt_str_sub(const char* s, long long start, long long n) { return str_sub(s, start, n); }
const char* srt_str_from_int(long long v) {
    char tmp[24];
    int n = srt_fmt_int(tmp, v);
    char* r = (char*)arena_alloc(strata_str_arena(), (size_t)n + 1);
    memcpy(r, tmp, (size_t)n + 1);
    return r;
}

const char* srt_read_file(const char* path)                  { return strata_read_file(path); }
bool        srt_write_file(const char* path, const char* d)  { return strata_write_file(path, d); }
void        srt_args(Array* out)                             { *out = strata_args(); }

void srt_arr_push(Array* a, const void* elem) { arr_push(a, elem); }

void srt_mat4_mul(mat4* r, const mat4* a, const mat4* b)        { *r = mat4_mul(*a, *b); }
void srt_mat4_mul_vec4(vec4* r, const mat4* m, const vec4* v)   { *r = mat4_mul_vec4(*m, *v); }
void srt_quat_mul(quat* r, const quat* a, const quat* b)        { *r = quat_mul(*a, *b); }
void srt_mat4_identity(mat4* r)                                 { *r = mat4_identity(); }
void srt_quat_identity(quat* r)                                 { *r = quat_identity(); }
void srt_mat4_translate(mat4* r, const vec3* t)                 { *r = mat4_translate(*t); }
void srt_mat4_scale(mat4* r, const vec3* s)                     { *r = mat4_scale(*s); }
void srt_mat4_rotate(mat4* r, const vec3* axis, float angle)    { *r = mat4_rotate(*axis, angle); }
void srt_quat_axis_angle(quat* r, const vec3* axis, float angle) { *r = quat_axis_angle(*axis, angle); }
void srt_mat4_perspective(mat4* r, float fovy, float aspect, float zn, float zf) { *r = mat4_perspective(fovy, aspect, zn, zf); }
void srt_mat4_look_at(mat4* r, const vec3* eye, const vec3* center, const vec3* up) { *r = mat4_look_at(*eye, *center, *up); }
void srt_quat_normalize(quat* r, const quat* q)                 { *r = quat_normalize(*q); }
void srt_quat_rotate(vec3* r, const quat* q, const vec3* v)     { *r = quat_rotate(*q, *v); }
void srt_quat_to_mat4(mat4* r, const quat* q)                   { *r = quat_to_mat4(*q); }
