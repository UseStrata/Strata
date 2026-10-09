/* host_reloc.c - a Strata dll loaded somewhere else than where it asked to be (Windows).
 * The address it wants (0x180000000) is taken first, so the loader must move the dll and
 * apply its base relocations: its pointer to its own data (lib_name's string) must still
 * be right. */
#include <windows.h>
#include <stdio.h>

typedef const char* (*NameFn)(void);
typedef long long (*AddFn)(long long, long long);

int main(void) {
    void* blocker = VirtualAlloc((void*)0x180000000ULL, 1 << 20, MEM_RESERVE, PAGE_NOACCESS);
    HMODULE m = LoadLibraryA("mathlib.dll");
    if (!m) { printf("LoadLibrary failed (%lu)\n", GetLastError()); return 1; }
    NameFn name = (NameFn)(void*)GetProcAddress(m, "lib_name");
    AddFn add = (AddFn)(void*)GetProcAddress(m, "lib_add");
    if (!name || !add) { printf("GetProcAddress failed\n"); return 1; }
    printf("moved: %s\n", (blocker && (void*)m != (void*)0x180000000ULL) ? "yes" : "no");
    printf("lib_name() = %s\n", name());
    printf("lib_add(40, 2) = %lld\n", add(40, 2));
    return 0;
}
