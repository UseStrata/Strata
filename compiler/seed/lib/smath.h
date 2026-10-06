/* Copyright © 2026 Connor Rutberg */
/* smath.h - Strata's first-class vector math runtime (milestone 2).
 *
 * vec2/vec3/vec4 as plain float structs, with component-wise + - *, scalar scale, dot,
 * cross (vec3), length, normalize. The compiler lowers Strata's `a + b`, `a * s`, etc. to
 * these calls using the operand types the checker resolved. Header-only, `static inline`.
 *
 * Named smath.h (not math.h) so it never shadows the C standard <math.h> it pulls in.
 *
 * Part of the Strata RUNTIME (compiler/lib): GPL-3.0 WITH the runtime linking exception
 * (see ../../LICENSE-RUNTIME.md) - programs built with Strata are not covered by the GPL.
 */
#ifndef STRATA_SMATH_H
#define STRATA_SMATH_H

#include <math.h>

typedef struct { float x, y; }       vec2;
typedef struct { float x, y, z; }    vec3;
typedef struct { float x, y, z, w; } vec4;

/* ---- vec2 ---- */
static inline vec2  vec2_add(vec2 a, vec2 b)   { return (vec2){ a.x+b.x, a.y+b.y }; }
static inline vec2  vec2_sub(vec2 a, vec2 b)   { return (vec2){ a.x-b.x, a.y-b.y }; }
static inline vec2  vec2_mul(vec2 a, vec2 b)   { return (vec2){ a.x*b.x, a.y*b.y }; }
static inline vec2  vec2_scale(vec2 a, float s){ return (vec2){ a.x*s, a.y*s }; }
static inline float vec2_dot(vec2 a, vec2 b)   { return a.x*b.x + a.y*b.y; }
static inline float vec2_length(vec2 a)        { return sqrtf(vec2_dot(a, a)); }
static inline vec2  vec2_normalize(vec2 a)     { float l = vec2_length(a); if (l == 0.0f) { return a; } return vec2_scale(a, 1.0f/l); }

/* ---- vec3 ---- */
static inline vec3  vec3_add(vec3 a, vec3 b)   { return (vec3){ a.x+b.x, a.y+b.y, a.z+b.z }; }
static inline vec3  vec3_sub(vec3 a, vec3 b)   { return (vec3){ a.x-b.x, a.y-b.y, a.z-b.z }; }
static inline vec3  vec3_mul(vec3 a, vec3 b)   { return (vec3){ a.x*b.x, a.y*b.y, a.z*b.z }; }
static inline vec3  vec3_scale(vec3 a, float s){ return (vec3){ a.x*s, a.y*s, a.z*s }; }
static inline float vec3_dot(vec3 a, vec3 b)   { return a.x*b.x + a.y*b.y + a.z*b.z; }
static inline vec3  vec3_cross(vec3 a, vec3 b) { return (vec3){ a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x }; }
static inline float vec3_length(vec3 a)        { return sqrtf(vec3_dot(a, a)); }
static inline vec3  vec3_normalize(vec3 a)     { float l = vec3_length(a); if (l == 0.0f) { return a; } return vec3_scale(a, 1.0f/l); }

/* ---- vec4 ---- */
static inline vec4  vec4_add(vec4 a, vec4 b)   { return (vec4){ a.x+b.x, a.y+b.y, a.z+b.z, a.w+b.w }; }
static inline vec4  vec4_sub(vec4 a, vec4 b)   { return (vec4){ a.x-b.x, a.y-b.y, a.z-b.z, a.w-b.w }; }
static inline vec4  vec4_mul(vec4 a, vec4 b)   { return (vec4){ a.x*b.x, a.y*b.y, a.z*b.z, a.w*b.w }; }
static inline vec4  vec4_scale(vec4 a, float s){ return (vec4){ a.x*s, a.y*s, a.z*s, a.w*s }; }
static inline float vec4_dot(vec4 a, vec4 b)   { return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w; }
static inline float vec4_length(vec4 a)        { return sqrtf(vec4_dot(a, a)); }
static inline vec4  vec4_normalize(vec4 a)     { float l = vec4_length(a); if (l == 0.0f) { return a; } return vec4_scale(a, 1.0f/l); }

/* ---- mat4 (column-major, OpenGL convention: element (row,col) at m[col*4+row]) ---- */
typedef struct { float m[16]; } mat4;

static inline mat4 mat4_identity(void) {
    mat4 r = {0};
    r.m[0] = 1.0f; r.m[5] = 1.0f; r.m[10] = 1.0f; r.m[15] = 1.0f;
    return r;
}
static inline mat4 mat4_mul(mat4 a, mat4 b) {
    mat4 r;
    for (int c = 0; c < 4; c++) {
        for (int row = 0; row < 4; row++) {
            float s = 0.0f;
            for (int k = 0; k < 4; k++) { s += a.m[k*4 + row] * b.m[c*4 + k]; }
            r.m[c*4 + row] = s;
        }
    }
    return r;
}
static inline vec4 mat4_mul_vec4(mat4 m, vec4 v) {
    vec4 r;
    r.x = m.m[0]*v.x + m.m[4]*v.y + m.m[8]*v.z  + m.m[12]*v.w;
    r.y = m.m[1]*v.x + m.m[5]*v.y + m.m[9]*v.z  + m.m[13]*v.w;
    r.z = m.m[2]*v.x + m.m[6]*v.y + m.m[10]*v.z + m.m[14]*v.w;
    r.w = m.m[3]*v.x + m.m[7]*v.y + m.m[11]*v.z + m.m[15]*v.w;
    return r;
}
static inline mat4 mat4_translate(vec3 t) { mat4 r = mat4_identity(); r.m[12] = t.x; r.m[13] = t.y; r.m[14] = t.z; return r; }
static inline mat4 mat4_scale(vec3 s)     { mat4 r = mat4_identity(); r.m[0] = s.x;  r.m[5] = s.y;  r.m[10] = s.z; return r; }
static inline mat4 mat4_rotate(vec3 axis, float angle) {
    vec3 a = vec3_normalize(axis);
    float c = cosf(angle), s = sinf(angle), t = 1.0f - c;
    mat4 r = mat4_identity();
    r.m[0] = t*a.x*a.x + c;     r.m[4] = t*a.x*a.y - s*a.z; r.m[8]  = t*a.x*a.z + s*a.y;
    r.m[1] = t*a.x*a.y + s*a.z; r.m[5] = t*a.y*a.y + c;     r.m[9]  = t*a.y*a.z - s*a.x;
    r.m[2] = t*a.x*a.z - s*a.y; r.m[6] = t*a.y*a.z + s*a.x; r.m[10] = t*a.z*a.z + c;
    return r;
}
static inline mat4 mat4_perspective(float fovy, float aspect, float znear, float zfar) {
    float f = 1.0f / tanf(fovy * 0.5f);
    mat4 r = {0};
    r.m[0] = f/aspect; r.m[5] = f;
    r.m[10] = (zfar + znear) / (znear - zfar); r.m[11] = -1.0f;
    r.m[14] = (2.0f * zfar * znear) / (znear - zfar);
    return r;
}
static inline mat4 mat4_look_at(vec3 eye, vec3 center, vec3 up) {
    vec3 f = vec3_normalize(vec3_sub(center, eye));
    vec3 s = vec3_normalize(vec3_cross(f, up));
    vec3 u = vec3_cross(s, f);
    mat4 r = mat4_identity();
    r.m[0] = s.x;  r.m[4] = s.y;  r.m[8]  = s.z;
    r.m[1] = u.x;  r.m[5] = u.y;  r.m[9]  = u.z;
    r.m[2] = -f.x; r.m[6] = -f.y; r.m[10] = -f.z;
    r.m[12] = -vec3_dot(s, eye); r.m[13] = -vec3_dot(u, eye); r.m[14] = vec3_dot(f, eye);
    return r;
}

/* ---- quat (x,y,z,w) ---- */
typedef struct { float x, y, z, w; } quat;

static inline quat quat_identity(void) { return (quat){ 0.0f, 0.0f, 0.0f, 1.0f }; }
static inline quat quat_mul(quat a, quat b) {
    return (quat){
        a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
        a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
        a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w,
        a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z
    };
}
static inline quat quat_axis_angle(vec3 axis, float angle) {
    vec3 a = vec3_normalize(axis);
    float h = angle * 0.5f, s = sinf(h);
    return (quat){ a.x*s, a.y*s, a.z*s, cosf(h) };
}
static inline quat quat_normalize(quat q) {
    float l = sqrtf(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
    if (l == 0.0f) { return q; }
    return (quat){ q.x/l, q.y/l, q.z/l, q.w/l };
}
static inline vec3 quat_rotate(quat q, vec3 v) {
    vec3 u = (vec3){ q.x, q.y, q.z };
    vec3 t = vec3_scale(vec3_cross(u, v), 2.0f);
    return vec3_add(vec3_add(v, vec3_scale(t, q.w)), vec3_cross(u, t));
}
static inline mat4 quat_to_mat4(quat q) {
    float x = q.x, y = q.y, z = q.z, w = q.w;
    mat4 r = mat4_identity();
    r.m[0] = 1.0f - 2.0f*(y*y + z*z); r.m[4] = 2.0f*(x*y - w*z);        r.m[8]  = 2.0f*(x*z + w*y);
    r.m[1] = 2.0f*(x*y + w*z);        r.m[5] = 1.0f - 2.0f*(x*x + z*z); r.m[9]  = 2.0f*(y*z - w*x);
    r.m[2] = 2.0f*(x*z - w*y);        r.m[6] = 2.0f*(y*z + w*x);        r.m[10] = 1.0f - 2.0f*(x*x + y*y);
    return r;
}

#endif /* STRATA_SMATH_H */
