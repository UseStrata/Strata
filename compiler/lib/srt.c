/* Copyright © 2026 Connor Rutberg */
/* srt.c - the runtime entry points for programs compiled by Strata's NATIVE backend.
 *
 * Natively compiled code (src/lower.strata, src/x64.strata) does its own arithmetic,
 * control flow and vector math, and calls these `srt_*` functions for the rest: printing,
 * arenas, strings, dynamic arrays, files, matrices and quaternions. They wrap the same
 * header-only runtime the C backend uses, so both backends behave alike.
 *
 * Structs travel by pointer (results through the first argument), so no struct-passing
 * rules are involved. This file is compiled with the C compiler for now; it is the next
 * piece to be rewritten in Strata itself.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <arena.h>
#include <smath.h>
#include <sstr.h>
#include <sio.h>
#include <sarr.h>

void srt_set_args(int argc, char** argv) { strata_set_args(argc, argv); }

void srt_print_i64(long long v)    { printf("%lld\n", v); }
void srt_print_f64(double v)       { printf("%g\n", v); }
void srt_print_str(const char* s)  { printf("%s\n", s); }

void* srt_arena_alloc(Arena* a, long long size) { return arena_alloc(a, (size_t)size); }
void  srt_arena_free(Arena* a)                  { arena_free(a); }
void* srt_heap_alloc(long long size)            { return arena_alloc(strata_heap(), (size_t)size); }

const char* srt_str_concat(const char* a, const char* b)          { return str_concat(a, b); }
int         srt_str_eq(const char* a, const char* b)              { return str_eq(a, b); }
long long   srt_str_len(const char* s)                            { return str_len(s); }
const char* srt_str_sub(const char* s, long long start, long long n) { return str_sub(s, start, n); }
const char* srt_str_from_int(long long v)                         { return str_from_int(v); }

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
