/*
 * msvc_stubs.c — MSVC runtime compatibility stubs for MinGW linking of CUDA objects.
 *
 * When nvcc uses cl.exe as host compiler on Windows, the resulting object files
 * and NVIDIA's cudart.lib contain references to MSVC-specific runtime symbols
 * that are not present in MinGW's libraries:
 *
 *   __security_cookie          — MSVC /GS stack buffer protection global
 *   __security_check_cookie    — MSVC /GS stack check function
 *   __GSHandlerCheck            — MSVC SEH frame handler for /GS
 *   __local_stdio_printf_options — UCRT internal printf option flags
 *   __local_stdio_scanf_options  — UCRT internal scanf option flags
 *
 * Compiled by MinGW gcc (plain C, no nvcc), this file provides inert stubs
 * so MinGW's ld can link the final DLL without MSVC's vcruntime.lib.
 *
 * Safety: PICLas runs under MinGW/MSYS2, not MSVC's CRT, so these MSVC
 * security mechanisms are irrelevant at runtime.  The stubs are safe no-ops.
 */
#include <stdint.h>

/* -------------------------------------------------------------------------
 * MSVC /GS buffer security check
 * cudart_static_loader.obj (inside NVIDIA's cudart.lib) references these.
 * Our own .cu files are compiled with /GS- so they do NOT reference them,
 * but cudart.lib is pre-compiled by NVIDIA with /GS enabled.
 * ------------------------------------------------------------------------- */
uintptr_t __security_cookie = (uintptr_t)0x2B992DDFA232ULL;

void __security_check_cookie(uintptr_t cookie)
{
    (void)cookie;   /* no-op: MinGW does not use MSVC stack protection */
}

void __GSHandlerCheck(void)
{
    /* no-op: MinGW SEH does not use MSVC's guard-stack frame handler */
}

/* -------------------------------------------------------------------------
 * UCRT internal stdio option flags
 * MinGW UCRT64's libmsvcrt.a wrappers and libaws-c-common.a call these
 * UCRT-internal functions when MSVC static-CRT objects (from cudart.lib)
 * are mixed into the same link and shift the printf resolution order.
 * Returning a pointer to a zero-initialised static is equivalent to the
 * default "no special options" state that UCRT uses before any flags are set.
 * ------------------------------------------------------------------------- */
unsigned long long *__local_stdio_printf_options(void)
{
    static unsigned long long opts = 0;
    return &opts;
}

unsigned long long *__local_stdio_scanf_options(void)
{
    static unsigned long long opts = 0;
    return &opts;
}

/* -------------------------------------------------------------------------
 * printf / fprintf
 * nvcc uses its own <cstdio> stub that declares printf as a plain external
 * reference rather than MSVC's inline UCRT wrapper.  The resulting CUDA
 * host objects therefore reference bare `printf` / `fprintf` symbols that
 * MinGW's import libraries do not export directly (MinGW implements printf
 * as an internal wrapper calling __mingw_vprintf / vprintf).
 * Provide thin forwarding stubs compiled by MinGW gcc so the symbols exist;
 * with --allow-multiple-definition these win over any later duplicate.
 * They delegate to vprintf / vfprintf which MinGW always provides.
 * ------------------------------------------------------------------------- */
#include <stdio.h>
#include <stdarg.h>

/* -------------------------------------------------------------------------
 * MSVC C++11 thread-safe static initialization
 * nvcc-generated host code for __global__ kernel registration uses MSVC's
 * thread-safe static init protocol even without <<<>>> syntax.
 *
 * _Init_thread_epoch  — per-thread TLS epoch counter (MSVC __declspec(thread))
 * _Init_thread_header — acquire "lock" before initializing a local static
 * _Init_thread_footer — release "lock" after successful initialization
 *
 * Stubs: single-threaded no-op (PICLas GPU init runs on one thread).
 * _Init_thread_epoch declared __declspec(thread) so the COFF SECREL
 * relocation in particle_push.cu.obj resolves to a valid TLS-section offset.
 * ------------------------------------------------------------------------- */
__declspec(thread) int _Init_thread_epoch = -1;

void _Init_thread_header(int *guard)
{
    if (*guard == 0) *guard = 1;   /* mark: initialization in progress */
}

void _Init_thread_footer(int *epoch)
{
    *epoch = -1;                   /* mark: initialization complete */
}

int printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vprintf(fmt, ap);
    va_end(ap);
    return r;
}

int fprintf(FILE *stream, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int r = vfprintf(stream, fmt, ap);
    va_end(ap);
    return r;
}

/* -------------------------------------------------------------------------
 * Private UCRT import redirects — eliminate api-ms-win-crt-private dependency
 *
 * MSVC-compiled objects in cudart.lib (compiled with /MD) reference basic
 * C runtime functions (memcpy, memcmp, memmove, memchr, strchr, strrchr,
 * strstr) via MSVC DLL import thunks: `call [__imp_memcpy]` etc.  GNU ld
 * creates an IAT entry for api-ms-win-crt-private-l1-1-0.dll for each such
 * reference, causing a runtime DLL-not-found failure because this private
 * UCRT DLL is only in System32\downlevel\ (not the standard search path).
 *
 * Fix: define __imp_xxx as function pointers pointing at MinGW's own
 * implementations.  GNU ld resolves the MSVC relocation to our local
 * pointer variable instead of creating an IAT entry, so the private CRT
 * DLL dependency disappears entirely from libpiclas.dll's import table.
 * ------------------------------------------------------------------------- */
#include <string.h>

void *(*__imp_memchr)(const void *, int, size_t)               = (void *(*)(const void *, int, size_t))memchr;
int   (*__imp_memcmp)(const void *, const void *, size_t)      = memcmp;
void *(*__imp_memcpy)(void *, const void *, size_t)            = memcpy;
void *(*__imp_memmove)(void *, const void *, size_t)           = memmove;
char *(*__imp_strchr)(const char *, int)                        = (char *(*)(const char *, int))strchr;
char *(*__imp_strrchr)(const char *, int)                       = (char *(*)(const char *, int))strrchr;
char *(*__imp_strstr)(const char *, const char *)               = (char *(*)(const char *, const char *))strstr;

