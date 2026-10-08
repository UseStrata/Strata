/* Copyright © 2026 Connor Rutberg */
/* crossplatform.h - one-file platform layer for Strata programs and C/C++ code.
 *
 * Single-header library: the declarations are always visible; the implementation is
 * compiled only where it's switched on. The Strata compiler itself uses it for
 * everything that differs between operating systems (see src/strata_host.h).
 *
 * USING IT
 *   Strata:  import <crossplatform.h>
 *            The implementation switches on automatically (stratac defines
 *            STRATA_PROGRAM in a program's one C file, or in a split build's main file).
 *   C/C++:   #include "crossplatform.h" anywhere, and in exactly ONE .c/.cpp file:
 *                #define STRATA_CROSSPLATFORM
 *                #include "crossplatform.h"
 *
 * OPTIONS (define before including)
 *   STRATA_CROSSPLATFORM_STATIC     every function is `static inline`: private to the one
 *                                   file that includes the implementation (no symbols
 *                                   exported from a dll, no clash with another copy)
 *   STRATA_CROSSPLATFORM_NO_<NAME>  leave a section out, e.g. to avoid linking its OS
 *                                   libraries
 *
 * SECTIONS
 *   Window   a native window                     opt out: STRATA_CROSSPLATFORM_NO_WINDOW
 *   System   OS name, core count, exe/dll paths  opt out: STRATA_CROSSPLATFORM_NO_SYSTEM
 *   Files    file/folder tests, mkdir -p         opt out: STRATA_CROSSPLATFORM_NO_FILES
 *   Process  start programs, wait for them       opt out: STRATA_CROSSPLATFORM_NO_PROCESS
 *
 * LINKING (per section)
 *   Window   Windows: user32, Linux: X11, macOS: -framework Cocoa. A Strata program that
 *            imports this header links them automatically (MSVC and MinGW link user32
 *            by default anyway).
 *   System   Linux:   dl, on glibc older than 2.34 (PlatformModulePath uses dladdr)
 *   Files, Process: nothing extra.
 *   On Linux with a strict -std=c99/c11, compile with -D_DEFAULT_SOURCE (the Files,
 *   System and Process sections use POSIX functions).
 *
 * ADDING A SECTION
 *   1. declarations in the DECLARATIONS part, inside #ifndef STRATA_CROSSPLATFORM_NO_<NAME>
 *   2. its OS headers in the PLATFORM part, under the same guard
 *   3. the implementation in the IMPLEMENTATION part, one #if branch per platform
 *   4. list it under SECTIONS and LINKING above
 *   Keep <windows.h> out of sections other than Window: its macros collide with ordinary
 *   names in generated C (the compiler includes this header with the Window section off).
 */

/* ============================== DECLARATIONS ============================== */

#ifndef STRATA_CROSSPLATFORM_H
#define STRATA_CROSSPLATFORM_H

#ifdef STRATA_CROSSPLATFORM_STATIC
#define STRATA_CP_API static inline
#else
#define STRATA_CP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Window ---------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_WINDOW

    /* Creates and shows a window whose client area is width x height. title is UTF-8. */
    STRATA_CP_API void CreatePlatformWindow(int width, int height, const char* title);

    /* Processes pending OS events. Returns 1 while the window is open, 0 once it has been closed. */
    STRATA_CP_API int PlatformPollEvents(void);

    /* Changes the window title (UTF-8). */
    STRATA_CP_API void PlatformSetWindowTitle(const char* title);

    /* Resizes the window's client area. */
    STRATA_CP_API void PlatformSetWindowSize(int width, int height);

    /* Current client-area size, including after the user resizes the window. */
    STRATA_CP_API int PlatformGetWindowWidth(void);
    STRATA_CP_API int PlatformGetWindowHeight(void);

    /* Closes the window. PlatformPollEvents returns 0 afterwards. */
    STRATA_CP_API void PlatformCloseWindow(void);

#endif /* STRATA_CROSSPLATFORM_NO_WINDOW */

/* ---- System ---------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_SYSTEM

    /* "windows", "macos" or "linux". */
    STRATA_CP_API const char* PlatformName(void);

    /* The CPU this was compiled for: "x86_64", "arm64", or "unknown". */
    STRATA_CP_API const char* PlatformArch(void);

    /* How many CPU cores are online (at least 1). */
    STRATA_CP_API int PlatformCpuCount(void);

    /* The running executable's full path, written to buf (NUL-terminated). Returns its
     * length, or 0 if it isn't known or doesn't fit. */
    STRATA_CP_API int PlatformExecutablePath(char* buf, int size);

    /* The full path of the executable or shared library (dll / .so / .dylib) containing
     * `address` - pass the address of one of its functions. Returns the length, or 0. */
    STRATA_CP_API int PlatformModulePath(const void* address, char* buf, int size);

#endif /* STRATA_CROSSPLATFORM_NO_SYSTEM */

/* ---- Files ----------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_FILES

    /* 1 if something (a file or a folder) exists at path, else 0. */
    STRATA_CP_API int PlatformPathExists(const char* path);

    /* 1 if path is a folder, else 0. */
    STRATA_CP_API int PlatformIsDirectory(const char* path);

    /* Creates the folder and any missing parents (like mkdir -p). `/` and, on Windows,
     * `\` separate folders. Returns 1 if the folder exists afterwards, else 0. */
    STRATA_CP_API int PlatformMakeDirectories(const char* path);

#endif /* STRATA_CROSSPLATFORM_NO_FILES */

/* ---- Process --------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_PROCESS

    /* A started program: a process handle on Windows, a pid elsewhere. 0 = none. */
    typedef long long PlatformProcess;

    /* Starts a program without a shell. argv is NULL-terminated; argv[0] is the program,
     * searched for on PATH unless it contains a folder. Each argument reaches the program
     * exactly as given (spaces and quotes included). The program shares this process's
     * console / stdout / stderr (pending stdio output is flushed first). Returns 0 if it
     * couldn't be started. */
    STRATA_CP_API PlatformProcess PlatformStartProcess(const char* const* argv);

    /* Waits for a started program to finish. Returns its exit code; -1 if it couldn't be
     * waited for; 128 + the signal number if a signal killed it (not on Windows). */
    STRATA_CP_API int PlatformWaitProcess(PlatformProcess process);

    /* PlatformStartProcess + PlatformWaitProcess. Returns -1 if it couldn't be started. */
    STRATA_CP_API int PlatformRunProcess(const char* const* argv);

#endif /* STRATA_CROSSPLATFORM_NO_PROCESS */

#ifdef __cplusplus
}
#endif

#endif /* STRATA_CROSSPLATFORM_H */

/* ============================= IMPLEMENTATION ============================= */

#if defined(STRATA_CROSSPLATFORM) || defined(STRATA_PROGRAM)
#ifndef STRATA_CROSSPLATFORM_IMPLEMENTED
#define STRATA_CROSSPLATFORM_IMPLEMENTED

/* ---- PLATFORM: detection + OS headers (outside extern "C") ----------------- */

#if defined(_WIN32)
    #define STRATA__WINDOWS 1
    #ifndef STRATA_CROSSPLATFORM_NO_WINDOW
    #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
    #endif
    #include <windows.h>
    #endif
    #if !defined(STRATA_CROSSPLATFORM_NO_FILES)
    #include <direct.h>      /* _mkdir */
    #include <sys/types.h>
    #include <sys/stat.h>    /* _stat */
    #include <errno.h>
    #endif
    #if !defined(STRATA_CROSSPLATFORM_NO_PROCESS)
    #include <process.h>     /* _spawnvp, _cwait */
    #endif
#elif defined(__APPLE__)
    #define STRATA__MACOS 1
    #ifndef STRATA_CROSSPLATFORM_NO_WINDOW
    #include <objc/runtime.h>
    #include <objc/message.h>
    #include <CoreGraphics/CoreGraphics.h>
    #endif
#elif defined(__linux__)
    #define STRATA__LINUX 1
    #ifndef _DEFAULT_SOURCE
    #define _DEFAULT_SOURCE  /* POSIX functions under a strict -std (only if included first) */
    #endif
    #ifndef STRATA_CROSSPLATFORM_NO_WINDOW
    #include <X11/Xlib.h>
    #include <X11/Xutil.h>
    #endif
#else
    #error "crossplatform.h: unsupported platform (expected Windows, macOS or Linux)"
#endif

#if !defined(STRATA__WINDOWS)   /* the POSIX sections (macOS and Linux) */
    #if !defined(STRATA_CROSSPLATFORM_NO_SYSTEM)
    #include <unistd.h>      /* sysconf, readlink */
    #include <stdlib.h>      /* realpath */
    #if defined(STRATA__MACOS) || defined(__USE_GNU)
    #include <dlfcn.h>       /* dladdr, Dl_info */
    #define STRATA__HAVE_DL_INFO 1
    #endif
    #if defined(STRATA__MACOS)
    #include <mach-o/dyld.h> /* _NSGetExecutablePath */
    #endif
    #endif
    #if !defined(STRATA_CROSSPLATFORM_NO_FILES)
    #include <sys/types.h>
    #include <sys/stat.h>    /* stat, mkdir */
    #include <errno.h>
    #endif
    #if !defined(STRATA_CROSSPLATFORM_NO_PROCESS)
    #include <spawn.h>       /* posix_spawnp */
    #include <sys/wait.h>    /* waitpid */
    #include <errno.h>
    #if defined(STRATA__MACOS)
    #include <crt_externs.h> /* _NSGetEnviron: `environ` isn't linkable from a dylib */
    #endif
    #endif
#endif

#if !defined(STRATA_CROSSPLATFORM_NO_FILES) || !defined(STRATA_CROSSPLATFORM_NO_SYSTEM) || !defined(STRATA_CROSSPLATFORM_NO_PROCESS)
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Window ---------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_WINDOW

    static int strata__width = 0;
    static int strata__height = 0;

    STRATA_CP_API int PlatformGetWindowWidth(void) { return strata__width; }
    STRATA_CP_API int PlatformGetWindowHeight(void) { return strata__height; }

#if defined(STRATA__WINDOWS)
#ifdef _MSC_VER
#pragma comment(lib, "user32.lib")
#endif

#define STRATA__STYLE WS_OVERLAPPEDWINDOW

    static HWND strata__hwnd = NULL;

    static LRESULT CALLBACK strata__WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
        switch (msg) {
        case WM_SIZE:
            if (wParam != SIZE_MINIMIZED) {
                strata__width = LOWORD(lParam);
                strata__height = HIWORD(lParam);
            }
            return 0;
        case WM_CLOSE:
            DestroyWindow(hwnd);
            return 0;
        case WM_DESTROY:
            strata__hwnd = NULL;
            return 0;
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    static void strata__widen(const char* utf8, wchar_t* out, int outLen) {
        if (!utf8 || !MultiByteToWideChar(CP_UTF8, 0, utf8, -1, out, outLen))
            out[0] = L'\0';
    }

    STRATA_CP_API void CreatePlatformWindow(int width, int height, const char* title) {
        static const wchar_t* className = L"StrataWindowClass";
        static int registered = 0;
        HINSTANCE instance = GetModuleHandleW(NULL);
        RECT rect = { 0, 0, width, height };
        wchar_t wtitle[256];

        if (strata__hwnd) return;

        if (!registered) {
            WNDCLASSEXW wc;
            ZeroMemory(&wc, sizeof(wc));
            wc.cbSize = sizeof(wc);
            wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
            wc.lpfnWndProc = strata__WndProc;
            wc.hInstance = instance;
            wc.hCursor = LoadCursor(NULL, IDC_ARROW);
            wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
            wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
            wc.lpszClassName = className;
            if (!RegisterClassExW(&wc)) return;
            registered = 1;
        }

        /* Grow the outer rect so the client area is exactly width x height. */
        AdjustWindowRect(&rect, STRATA__STYLE, FALSE);
        strata__widen(title, wtitle, 256);

        strata__hwnd = CreateWindowExW(0, className, wtitle, STRATA__STYLE,
            CW_USEDEFAULT, CW_USEDEFAULT,
            rect.right - rect.left, rect.bottom - rect.top,
            NULL, NULL, instance, NULL);
        if (!strata__hwnd) return;

        strata__width = width;
        strata__height = height;
        ShowWindow(strata__hwnd, SW_SHOW);
        UpdateWindow(strata__hwnd);
    }

    STRATA_CP_API int PlatformPollEvents(void) {
        MSG msg;
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        return strata__hwnd != NULL;
    }

    STRATA_CP_API void PlatformSetWindowTitle(const char* title) {
        wchar_t wtitle[256];
        if (!strata__hwnd) return;
        strata__widen(title, wtitle, 256);
        SetWindowTextW(strata__hwnd, wtitle);
    }

    STRATA_CP_API void PlatformSetWindowSize(int width, int height) {
        RECT rect = { 0, 0, width, height };
        if (!strata__hwnd) return;
        AdjustWindowRect(&rect, STRATA__STYLE, FALSE);
        SetWindowPos(strata__hwnd, NULL, 0, 0, rect.right - rect.left, rect.bottom - rect.top,
            SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    }

    STRATA_CP_API void PlatformCloseWindow(void) {
        if (strata__hwnd) DestroyWindow(strata__hwnd);
    }

#undef STRATA__STYLE

#elif defined(STRATA__MACOS)
    /* Plain C Cocoa via the Objective-C runtime, so this header works from .c/.cpp files. */

#define strata__cls(name) ((id)objc_getClass(name))
#define strata__sel(name) sel_registerName(name)

    static id  strata__app = NULL;
    static id  strata__window = NULL;
    static int strata__open = 0;

    static id strata__pool(void) {
        return ((id(*)(id, SEL))objc_msgSend)(strata__cls("NSAutoreleasePool"), strata__sel("new"));
    }

    static void strata__drain(id pool) {
        ((void (*)(id, SEL))objc_msgSend)(pool, strata__sel("drain"));
    }

    static id strata__nsstring(const char* utf8) {
        return ((id(*)(id, SEL, const char*))objc_msgSend)(
            strata__cls("NSString"), strata__sel("stringWithUTF8String:"), utf8 ? utf8 : "");
    }

    static void strata__updateSize(void) {
        id view = ((id(*)(id, SEL))objc_msgSend)(strata__window, strata__sel("contentView"));
        CGRect frame;
#if defined(__x86_64__)
        frame = ((CGRect(*)(id, SEL))objc_msgSend_stret)(view, strata__sel("frame"));
#else
        frame = ((CGRect(*)(id, SEL))objc_msgSend)(view, strata__sel("frame"));
#endif
        strata__width = (int)frame.size.width;
        strata__height = (int)frame.size.height;
    }

    static void strata__windowWillClose(id self, SEL cmd, id notification) {
        (void)self; (void)cmd; (void)notification;
        strata__open = 0;
    }

    static void strata__windowDidResize(id self, SEL cmd, id notification) {
        (void)self; (void)cmd; (void)notification;
        strata__updateSize();
    }

    STRATA_CP_API void CreatePlatformWindow(int width, int height, const char* title) {
        id pool, delegate;
        Class delegateClass;
        CGRect frame;
        /* NSWindowStyleMaskTitled | Closable | Miniaturizable | Resizable */
        unsigned long styleMask = 1 | 2 | 4 | 8;

        if (strata__open) return;

        pool = strata__pool();

        strata__app = ((id(*)(id, SEL))objc_msgSend)(strata__cls("NSApplication"), strata__sel("sharedApplication"));
        /* NSApplicationActivationPolicyRegular: dock icon + menu bar even without an app bundle. */
        ((void (*)(id, SEL, long))objc_msgSend)(strata__app, strata__sel("setActivationPolicy:"), 0);
        ((void (*)(id, SEL))objc_msgSend)(strata__app, strata__sel("finishLaunching"));

        frame = CGRectMake(0, 0, width, height);
        strata__window = ((id(*)(id, SEL))objc_msgSend)(strata__cls("NSWindow"), strata__sel("alloc"));
        strata__window = ((id(*)(id, SEL, CGRect, unsigned long, unsigned long, BOOL))objc_msgSend)(
            strata__window, strata__sel("initWithContentRect:styleMask:backing:defer:"),
            frame, styleMask, 2 /* NSBackingStoreBuffered */, NO);
        if (!strata__window) {
            strata__drain(pool);
            return;
        }
        ((void (*)(id, SEL, BOOL))objc_msgSend)(strata__window, strata__sel("setReleasedWhenClosed:"), NO);

        /* Delegate class that tracks close and resize. */
        delegateClass = objc_getClass("StrataWindowDelegate");
        if (!delegateClass) {
            delegateClass = objc_allocateClassPair(objc_getClass("NSObject"), "StrataWindowDelegate", 0);
            class_addMethod(delegateClass, strata__sel("windowWillClose:"), (IMP)strata__windowWillClose, "v@:@");
            class_addMethod(delegateClass, strata__sel("windowDidResize:"), (IMP)strata__windowDidResize, "v@:@");
            objc_registerClassPair(delegateClass);
        }
        delegate = ((id(*)(id, SEL))objc_msgSend)((id)delegateClass, strata__sel("new"));
        ((void (*)(id, SEL, id))objc_msgSend)(strata__window, strata__sel("setDelegate:"), delegate);

        ((void (*)(id, SEL, id))objc_msgSend)(strata__window, strata__sel("setTitle:"), strata__nsstring(title));
        ((void (*)(id, SEL))objc_msgSend)(strata__window, strata__sel("center"));
        ((void (*)(id, SEL, id))objc_msgSend)(strata__window, strata__sel("makeKeyAndOrderFront:"), (id)NULL);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(strata__app, strata__sel("activateIgnoringOtherApps:"), YES);

        strata__width = width;
        strata__height = height;
        strata__open = 1;
        strata__drain(pool);
    }

    STRATA_CP_API int PlatformPollEvents(void) {
        id pool, event, distantPast, mode;

        if (!strata__app) return 0;

        pool = strata__pool();
        distantPast = ((id(*)(id, SEL))objc_msgSend)(strata__cls("NSDate"), strata__sel("distantPast"));
        mode = strata__nsstring("kCFRunLoopDefaultMode"); /* NSDefaultRunLoopMode */

        for (;;) {
            event = ((id(*)(id, SEL, unsigned long long, id, id, BOOL))objc_msgSend)(
                strata__app, strata__sel("nextEventMatchingMask:untilDate:inMode:dequeue:"),
                ~0ULL /* NSEventMaskAny */, distantPast, mode, YES);
            if (!event) break;
            ((void (*)(id, SEL, id))objc_msgSend)(strata__app, strata__sel("sendEvent:"), event);
        }
        ((void (*)(id, SEL))objc_msgSend)(strata__app, strata__sel("updateWindows"));

        strata__drain(pool);
        return strata__open;
    }

    STRATA_CP_API void PlatformSetWindowTitle(const char* title) {
        id pool;
        if (!strata__open) return;
        pool = strata__pool();
        ((void (*)(id, SEL, id))objc_msgSend)(strata__window, strata__sel("setTitle:"), strata__nsstring(title));
        strata__drain(pool);
    }

    STRATA_CP_API void PlatformSetWindowSize(int width, int height) {
        if (!strata__open) return;
        ((void (*)(id, SEL, CGSize))objc_msgSend)(strata__window, strata__sel("setContentSize:"),
            CGSizeMake(width, height));
        strata__updateSize();
    }

    STRATA_CP_API void PlatformCloseWindow(void) {
        if (strata__open)
            ((void (*)(id, SEL))objc_msgSend)(strata__window, strata__sel("close"));
    }

#undef strata__cls
#undef strata__sel

#elif defined(STRATA__LINUX)

    static Display* strata__display = NULL;
    static Window   strata__window = 0;
    static Atom     strata__wmDeleteWindow;
    static int      strata__open = 0;

    STRATA_CP_API void CreatePlatformWindow(int width, int height, const char* title) {
        int screen;

        if (strata__open) return;

        strata__display = XOpenDisplay(NULL);
        if (!strata__display) return;

        screen = DefaultScreen(strata__display);
        strata__window = XCreateSimpleWindow(strata__display, RootWindow(strata__display, screen),
            0, 0, (unsigned int)width, (unsigned int)height, 0,
            BlackPixel(strata__display, screen),
            BlackPixel(strata__display, screen));

        XStoreName(strata__display, strata__window, title ? title : "");
        XSelectInput(strata__display, strata__window,
            ExposureMask | KeyPressMask | KeyReleaseMask |
            ButtonPressMask | ButtonReleaseMask | PointerMotionMask |
            StructureNotifyMask | FocusChangeMask);

        /* Ask the window manager to send us a message instead of killing the connection on close. */
        strata__wmDeleteWindow = XInternAtom(strata__display, "WM_DELETE_WINDOW", False);
        XSetWMProtocols(strata__display, strata__window, &strata__wmDeleteWindow, 1);

        XMapWindow(strata__display, strata__window);
        XFlush(strata__display);
        strata__width = width;
        strata__height = height;
        strata__open = 1;
    }

    STRATA_CP_API void PlatformCloseWindow(void) {
        if (!strata__open) return;
        XDestroyWindow(strata__display, strata__window);
        XCloseDisplay(strata__display);
        strata__display = NULL;
        strata__window = 0;
        strata__open = 0;
    }

    STRATA_CP_API int PlatformPollEvents(void) {
        XEvent event;

        if (!strata__open) return 0;

        while (XPending(strata__display)) {
            XNextEvent(strata__display, &event);
            if (event.type == ConfigureNotify) {
                strata__width = event.xconfigure.width;
                strata__height = event.xconfigure.height;
            }
            else if (event.type == ClientMessage &&
                (Atom)event.xclient.data.l[0] == strata__wmDeleteWindow) {
                PlatformCloseWindow();
                return 0;
            }
        }
        return 1;
    }

    STRATA_CP_API void PlatformSetWindowTitle(const char* title) {
        if (!strata__open) return;
        XStoreName(strata__display, strata__window, title ? title : "");
        XFlush(strata__display);
    }

    STRATA_CP_API void PlatformSetWindowSize(int width, int height) {
        if (!strata__open) return;
        XResizeWindow(strata__display, strata__window, (unsigned int)width, (unsigned int)height);
        XFlush(strata__display);
        strata__width = width;
        strata__height = height;
    }

#endif /* platform */
#endif /* STRATA_CROSSPLATFORM_NO_WINDOW */

/* ---- System ---------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_SYSTEM

#if defined(STRATA__WINDOWS)
#ifndef _WINDOWS_
    /* Declared here rather than including <windows.h> (see ADDING A SECTION). */
    __declspec(dllimport) unsigned long __stdcall GetModuleFileNameA(void* module, char* path, unsigned long size);
    __declspec(dllimport) int __stdcall GetModuleHandleExA(unsigned long flags, const char* name, void** module);
    #define STRATA__HMODULE void*
    #define STRATA__LPCSTR const char*
#else
    #define STRATA__HMODULE HMODULE
    #define STRATA__LPCSTR LPCSTR
#endif

    STRATA_CP_API const char* PlatformName(void) { return "windows"; }

    STRATA_CP_API const char* PlatformArch(void) {
#if defined(__x86_64__) || defined(_M_X64)
        return "x86_64";
#elif defined(__aarch64__) || defined(_M_ARM64)
        return "arm64";
#else
        return "unknown";
#endif
    }

    STRATA_CP_API int PlatformCpuCount(void) {
        const char* n = getenv("NUMBER_OF_PROCESSORS");
        int v = n ? atoi(n) : 0;
        return v > 0 ? v : 1;
    }

    STRATA_CP_API int PlatformExecutablePath(char* buf, int size) {
        unsigned long n;
        if (!buf || size <= 0) return 0;
        n = GetModuleFileNameA(NULL, buf, (unsigned long)size);
        if (n == 0 || n >= (unsigned long)size) { buf[0] = '\0'; return 0; }
        return (int)n;
    }

    STRATA_CP_API int PlatformModulePath(const void* address, char* buf, int size) {
        STRATA__HMODULE mod = NULL;
        unsigned long n;
        if (!buf || size <= 0) return 0;
        buf[0] = '\0';
        /* 0x4 = GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, 0x2 = ..._UNCHANGED_REFCOUNT */
        if (!GetModuleHandleExA(0x4 | 0x2, (STRATA__LPCSTR)address, &mod)) return 0;
        n = GetModuleFileNameA(mod, buf, (unsigned long)size);
        if (n == 0 || n >= (unsigned long)size) { buf[0] = '\0'; return 0; }
        return (int)n;
    }

#undef STRATA__HMODULE
#undef STRATA__LPCSTR

#else /* macOS, Linux */

#if !defined(STRATA__HAVE_DL_INFO)
    /* glibc declares Dl_info / dladdr only with _GNU_SOURCE, which must come before the
     * first system header: declare the same layout here instead. */
    typedef struct { const char* dli_fname; void* dli_fbase; const char* dli_sname; void* dli_saddr; } Dl_info;
    extern int dladdr(const void* address, Dl_info* info);
#endif

    STRATA_CP_API const char* PlatformName(void) {
#if defined(STRATA__MACOS)
        return "macos";
#else
        return "linux";
#endif
    }

    STRATA_CP_API const char* PlatformArch(void) {
#if defined(__x86_64__) || defined(_M_X64)
        return "x86_64";
#elif defined(__aarch64__) || defined(_M_ARM64)
        return "arm64";
#else
        return "unknown";
#endif
    }

    STRATA_CP_API int PlatformCpuCount(void) {
        long v = sysconf(_SC_NPROCESSORS_ONLN);
        return v > 0 ? (int)v : 1;
    }

    /* Copy `path` (resolved to an absolute, symlink-free path if possible) into buf. */
    static int strata__put_path(const char* path, char* buf, int size) {
        char* real = realpath(path, NULL);
        const char* p = real ? real : path;
        size_t n = strlen(p);
        int ok = n > 0 && n < (size_t)size;
        if (ok) memcpy(buf, p, n + 1); else buf[0] = '\0';
        free(real);
        return ok ? (int)n : 0;
    }

    STRATA_CP_API int PlatformExecutablePath(char* buf, int size) {
        if (!buf || size <= 0) return 0;
        buf[0] = '\0';
#if defined(STRATA__MACOS)
        {
            char raw[4096];
            uint32_t len = sizeof raw;
            if (_NSGetExecutablePath(raw, &len) != 0) return 0;
            return strata__put_path(raw, buf, size);
        }
#else
        {
            char raw[4096];
            ssize_t n = readlink("/proc/self/exe", raw, sizeof raw - 1);
            if (n <= 0) return 0;
            raw[n] = '\0';
            return strata__put_path(raw, buf, size);
        }
#endif
    }

    STRATA_CP_API int PlatformModulePath(const void* address, char* buf, int size) {
        Dl_info info;
        if (!buf || size <= 0) return 0;
        buf[0] = '\0';
        if (!dladdr(address, &info) || !info.dli_fname || !info.dli_fname[0]) return 0;
        return strata__put_path(info.dli_fname, buf, size);
    }

#endif /* platform */
#endif /* STRATA_CROSSPLATFORM_NO_SYSTEM */

/* ---- Files ----------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_FILES

#if defined(STRATA__WINDOWS)
    #define STRATA__IS_SEP(c) ((c) == '/' || (c) == '\\')
    static int strata__stat_dir(const char* path, int* is_dir) {
        struct _stat st;
        if (_stat(path, &st) != 0) return 0;
        *is_dir = (st.st_mode & _S_IFDIR) != 0;
        return 1;
    }
    static int strata__mkdir(const char* path) { return _mkdir(path); }
#else
    #define STRATA__IS_SEP(c) ((c) == '/')
    static int strata__stat_dir(const char* path, int* is_dir) {
        struct stat st;
        if (stat(path, &st) != 0) return 0;
        *is_dir = S_ISDIR(st.st_mode) ? 1 : 0;
        return 1;
    }
    static int strata__mkdir(const char* path) { return mkdir(path, 0777); }
#endif

    STRATA_CP_API int PlatformPathExists(const char* path) {
        int is_dir = 0;
        return path && path[0] && strata__stat_dir(path, &is_dir);
    }

    STRATA_CP_API int PlatformIsDirectory(const char* path) {
        int is_dir = 0;
        return path && path[0] && strata__stat_dir(path, &is_dir) && is_dir;
    }

    STRATA_CP_API int PlatformMakeDirectories(const char* path) {
        size_t n, i, start = 0;
        char* p;
        int ok;
        if (!path || !path[0]) return 0;
        if (PlatformIsDirectory(path)) return 1;
        n = strlen(path);
        p = (char*)malloc(n + 1);
        if (!p) return 0;
        memcpy(p, path, n + 1);
#if defined(STRATA__WINDOWS)
        if (n >= 2 && p[1] == ':') start = 2;                       /* C:\... */
        else if (n >= 2 && STRATA__IS_SEP(p[0]) && STRATA__IS_SEP(p[1])) {
            /* \\server\share\...: skip the server and share names */
            int seps = 0;
            for (start = 2; start < n && seps < 2; start++) if (STRATA__IS_SEP(p[start])) seps++;
        }
#endif
        /* make each parent in turn ("a", "a/b", ...), then the folder itself */
        for (i = start + 1; i <= n; i++) {
            if (i == n || STRATA__IS_SEP(p[i])) {
                char saved = p[i];
                p[i] = '\0';
                if (!PlatformIsDirectory(p) && strata__mkdir(p) != 0 && errno != EEXIST) {
                    p[i] = saved;
                    break;
                }
                p[i] = saved;
            }
        }
        ok = PlatformIsDirectory(p);
        free(p);
        return ok;
    }

    #undef STRATA__IS_SEP

#endif /* STRATA_CROSSPLATFORM_NO_FILES */

/* ---- Process --------------------------------------------------------------- */
#ifndef STRATA_CROSSPLATFORM_NO_PROCESS

#if defined(STRATA__WINDOWS)
    /* _spawnvp joins argv into one command line WITHOUT quoting, and the program splits
     * it again; so quote each argument the way the C runtime parses them back. */
    static char* strata__quote_arg(const char* a) {
        size_t n = strlen(a), i, o = 0, slashes = 0;
        int needs = (n == 0) || strpbrk(a, " \t\n\v\"") != NULL;
        char* q;
        if (!needs) {
            q = (char*)malloc(n + 1);
            if (q) memcpy(q, a, n + 1);
            return q;
        }
        q = (char*)malloc(n * 2 + 3);
        if (!q) return NULL;
        q[o++] = '"';
        for (i = 0; i < n; i++) {
            if (a[i] == '\\') { slashes++; q[o++] = '\\'; continue; }
            if (a[i] == '"') {                     /* double the backslashes, escape the quote */
                while (slashes--) q[o++] = '\\';
                q[o++] = '\\';
            }
            slashes = 0;
            q[o++] = a[i];
        }
        while (slashes--) q[o++] = '\\';           /* backslashes before the closing quote */
        q[o++] = '"';
        q[o] = '\0';
        return q;
    }

    STRATA_CP_API PlatformProcess PlatformStartProcess(const char* const* argv) {
        size_t n = 0, i;
        char** quoted;
        intptr_t h;
        if (!argv || !argv[0]) return 0;
        while (argv[n]) n++;
        quoted = (char**)calloc(n + 1, sizeof(char*));
        if (!quoted) return 0;
        for (i = 0; i < n; i++) {
            quoted[i] = strata__quote_arg(argv[i]);
            if (!quoted[i]) { n = i; h = -1; goto done; }
        }
        fflush(NULL);
        h = _spawnvp(_P_NOWAIT, argv[0], (const char* const*)quoted);
    done:
        for (i = 0; i < n; i++) free(quoted[i]);
        free(quoted);
        return h == -1 ? 0 : (PlatformProcess)h;
    }

    STRATA_CP_API int PlatformWaitProcess(PlatformProcess process) {
        int status = 0;
        if (!process) return -1;
        if (_cwait(&status, (intptr_t)process, 0) == -1) return -1;
        return status;
    }

#else /* macOS, Linux */

    STRATA_CP_API PlatformProcess PlatformStartProcess(const char* const* argv) {
        pid_t pid;
#if defined(STRATA__MACOS)
        char** env = *_NSGetEnviron();
#else
        extern char** environ;
        char** env = environ;
#endif
        if (!argv || !argv[0]) return 0;
        fflush(NULL);
        if (posix_spawnp(&pid, argv[0], NULL, NULL, (char* const*)argv, env) != 0) return 0;
        return (PlatformProcess)pid;
    }

    STRATA_CP_API int PlatformWaitProcess(PlatformProcess process) {
        int status = 0;
        pid_t r;
        if (process <= 0) return -1;
        do { r = waitpid((pid_t)process, &status, 0); } while (r == -1 && errno == EINTR);
        if (r == -1) return -1;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        return -1;
    }

#endif /* platform */

    STRATA_CP_API int PlatformRunProcess(const char* const* argv) {
        PlatformProcess p = PlatformStartProcess(argv);
        return p ? PlatformWaitProcess(p) : -1;
    }

#endif /* STRATA_CROSSPLATFORM_NO_PROCESS */

#ifdef __cplusplus
}
#endif

#endif /* STRATA_CROSSPLATFORM_IMPLEMENTED */
#endif /* STRATA_CROSSPLATFORM || STRATA_PROGRAM */
