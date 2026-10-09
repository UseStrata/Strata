/* host_dll.c - a C program calling a dll WRITTEN IN STRATA (tests/projects/lib), through
 * the header stratac generated for it. */
#include <stdio.h>
#include "mathlib.h"
int main(void) {
    printf("lib_add(2, 3) = %lld\n", (long long)lib_add(2, 3));
    printf("lib_lerp(0, 10, 0.25) = %g\n", lib_lerp(0.0f, 10.0f, 0.25f));
    printf("lib_name() = %s\n", lib_name());
    return 0;
}
