/*
 * gpu_loader.c — Explicit LoadLibrary loader for libpiclasGPU.dll.
 *
 * PROBLEM: Windows DLL loader deadlock.
 * If libpiclas.dll statically links CUDA objects, their fat-binary registration
 * static initialiser runs during libpiclas.dll's DllMain while the Windows loader
 * lock is held.  CUDA's runtime creates background driver threads that also need
 * the loader lock → deadlock before main() ever runs (process hangs, no output).
 *
 * FIX: libpiclas.dll does NOT import CUDA symbols.  Instead, GPU_Init() in
 * gpu_interface.f90 calls piclas_gpu_load_library() which calls
 * LoadLibraryA("libpiclasGPU.dll") explicitly.  By that point main() has already
 * started and the loader lock is NOT held by the calling thread, so CUDA's driver
 * initialisation can spawn threads freely without deadlocking.
 *
 * The forwarding stubs below carry the same names as the real CUDA functions in
 * libpiclasGPU.dll.  The Fortran ISO_C_BINDING interface in gpu_interface.f90
 * therefore needs no changes — BIND(C, NAME='piclas_gpu_init') etc. resolve to
 * these stubs at link time, and the stubs delegate at runtime via GetProcAddress.
 *
 * Compiled by MinGW gcc (not nvcc/cl.exe) so it carries no MSVC CRT dependencies.
 */

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

/* ── function pointer types ──────────────────────────────────────────────── */
typedef void (*pfn_void)(void);
typedef void (*pfn_alloc)(int);
typedef void (*pfn_push)(double *, int *, int, double);
typedef void (*pfn_lserk)(double *, double *, double *,
                           int *, int *, int *,
                           int, int, double, double);

/* ── resolved pointers — NULL until piclas_gpu_load_library() is called ─── */
static pfn_void  g_gpu_init     = NULL;
static pfn_void  g_gpu_finalize = NULL;
static pfn_alloc g_gpu_alloc    = NULL;
static pfn_void  g_gpu_free     = NULL;
static pfn_push  g_gpu_push     = NULL;
static pfn_lserk g_gpu_lserk    = NULL;
static HMODULE   g_hGPULib      = NULL;

/* ── helper: resolve one symbol, abort if missing ───────────────────────── */
static FARPROC resolve(const char *name)
{
    FARPROC p = GetProcAddress(g_hGPULib, name);
    if (!p) {
        fprintf(stderr, "[GPU] GetProcAddress(\"%s\") failed: error %lu\n",
                name, (unsigned long)GetLastError());
        exit(EXIT_FAILURE);
    }
    return p;
}

/* ── piclas_gpu_load_library ─────────────────────────────────────────────
 * Called from Fortran GPU_Init() before the first CUDA API touch.
 * Loads libpiclasGPU.dll (and its IAT dependency cudart64_13.dll) after
 * main() has started so the Windows loader lock is not held by this thread.
 * ─────────────────────────────────────────────────────────────────────── */
void piclas_gpu_load_library(void)
{
    if (g_hGPULib) return;  /* already loaded */

    fprintf(stdout, "[GPU] Loading libpiclasGPU.dll ...\n"); fflush(stdout);

    g_hGPULib = LoadLibraryA("libpiclasGPU.dll");
    if (!g_hGPULib) {
        fprintf(stderr,
            "[GPU] Cannot load libpiclasGPU.dll (error %lu).\n"
            "      Ensure libpiclasGPU.dll and cudart64_13.dll are in the\n"
            "      same directory as piclas.exe (bin/).\n",
            (unsigned long)GetLastError());
        exit(EXIT_FAILURE);
    }

    g_gpu_init     = (pfn_void) resolve("piclas_gpu_init");
    g_gpu_finalize = (pfn_void) resolve("piclas_gpu_finalize");
    g_gpu_alloc    = (pfn_alloc)resolve("piclas_gpu_alloc_buffers");
    g_gpu_free     = (pfn_void) resolve("piclas_gpu_free_buffers");
    g_gpu_push     = (pfn_push) resolve("piclas_gpu_push_particles");
    g_gpu_lserk    = (pfn_lserk)resolve("piclas_gpu_lserk_stage");

    fprintf(stdout, "[GPU] libpiclasGPU.dll loaded.\n"); fflush(stdout);
}

/* ── forwarding stubs ────────────────────────────────────────────────────
 * Same names as the real CUDA functions; the Fortran BIND(C) interface
 * resolves to these at link time and they delegate via function pointers.
 * ─────────────────────────────────────────────────────────────────────── */
void piclas_gpu_init(void)
{
    g_gpu_init();
}

void piclas_gpu_finalize(void)
{
    g_gpu_finalize();
}

void piclas_gpu_alloc_buffers(int nMaxPart)
{
    g_gpu_alloc(nMaxPart);
}

void piclas_gpu_free_buffers(void)
{
    g_gpu_free();
}

void piclas_gpu_push_particles(double *PartState, int *isActive, int nPart, double dt)
{
    g_gpu_push(PartState, isActive, nPart, dt);
}

void piclas_gpu_lserk_stage(double *PartState, double *Pt_temp, double *Pt,
                             int *isActive, int *isPush, int *isNewPart,
                             int nPart, int isStage1, double RK_a, double b_dt)
{
    g_gpu_lserk(PartState, Pt_temp, Pt, isActive, isPush, isNewPart,
                nPart, isStage1, RK_a, b_dt);
}
