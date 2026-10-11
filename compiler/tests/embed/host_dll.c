/* host_dll.c - a C program calling a dll WRITTEN IN STRATA (tests/projects/lib), through
 * the header stratac generated for it. */
#include <stdio.h>
#include "mathlib.h"
/* a C function the dll calls back (its type: the header's typedef for fn(int, int) -> int) */
static int64_t sum(int64_t a, int64_t b) { return a + b; }
int main(void) {
    printf("lib_add(2, 3) = %lld\n", (long long)lib_add(2, 3));
    printf("lib_lerp(0, 10, 0.25) = %g\n", lib_lerp(0.0f, 10.0f, 0.25f));
    printf("lib_name() = %s\n", lib_name());
    MathOps* ops = lib_ops();     /* a struct of function pointers, filled in by Strata */
    printf("ops->combine(4, 5) = %lld\n", (long long)ops->combine(4, 5));
    printf("ops->twice(1.5) = %g\n", ops->twice(1.5f));
    printf("lib_fold(sum, 100, 5) = %lld\n", (long long)lib_fold(sum, 100, 5));
    return 0;
}
