/* host_api.c - a C "engine" embedding the Strata compiler through strata.h. */
#include <stdio.h>
#include <string.h>
#include "strata.h"
#if defined(_WIN32)
#include <windows.h>
#include <psapi.h>
#elif defined(__APPLE__)
#include <mach/mach.h>
#else
#include <unistd.h>
#endif

#if defined(_WIN32)
#define MAIN_EXE "prog/main.exe"
#define DLL_EXT ".dll"
#elif defined(__APPLE__)
#define MAIN_EXE "prog/main"
#define DLL_EXT ".dylib"
#else
#define MAIN_EXE "prog/main"
#define DLL_EXT ".so"
#endif

static void show(const char* what, bool ok) { printf("%s: %s\n", what, ok ? "ok" : "FAILED"); }

/* the process's resident memory, in MB */
static size_t memory_mb(void) {
#if defined(_WIN32)
    PROCESS_MEMORY_COUNTERS pmc;
    GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof pmc);
    return pmc.WorkingSetSize / (1024 * 1024);
#elif defined(__APPLE__)
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t n = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &n) != KERN_SUCCESS) return 0;
    return (size_t)info.resident_size / (1024 * 1024);
#else
    long pages = 0, resident = 0;
    FILE* f = fopen("/proc/self/statm", "r");
    if (f) { if (fscanf(f, "%ld %ld", &pages, &resident) != 2) resident = 0; fclose(f); }
    return (size_t)resident * (size_t)sysconf(_SC_PAGESIZE) / (1024 * 1024);
#endif
}

int main(void) {
    show("version", strlen(strata_version()) > 0);
    show("check good source", strata_check_source("prog/main.strata", "print(1 + 2)\n"));
    show("check bad source fails", !strata_check_source("prog/main.strata", "var x = 1 + true\nprint(nope)\n"));
    printf("%s", strata_diagnostics());
    show("check a file with a module", strata_check("prog/main.strata"));
    show("no diagnostics after success", strata_diagnostics()[0] == '\0');

    const char* c = strata_emit("prog/main.strata");
    show("emit", strstr(c, "int main(") != NULL && strstr(c, "shout") != NULL);
    show("emit of a bad program is empty", strata_emit_source("prog/main.strata", "print(nope)\n")[0] == '\0');

    show("build a file (lib/ found next to the dll)", strata_build("prog/main.strata", false, false));
    FILE* f = fopen(MAIN_EXE, "rb");
    show("the exe exists", f != NULL);
    if (f) fclose(f);
    show("build a dll project", strata_build("../projects/lib", false, false));
    show("output path", strstr(strata_output_path("../projects/lib"), "mathlib" DLL_EXT) != NULL);
    show("a bad target reports why", !strata_build("nowhere", false, false) && strstr(strata_diagnostics(), "no strata.toml in nowhere") != NULL);

    /* an engine recompiling on every save: memory must stay flat */
    for (int i = 0; i < 50; i++) { strata_check("prog/main.strata"); strata_emit("prog/main.strata"); strata_reset(); }
    size_t before = memory_mb();
    for (int i = 0; i < 300; i++) { strata_check("prog/main.strata"); strata_emit("prog/main.strata"); strata_reset(); }
    size_t after = memory_mb();
    show("300 more check+emit+reset cycles don't grow memory", after <= before + 8);
    show("still works after resets", strata_check("prog/main.strata"));
    return 0;
}
