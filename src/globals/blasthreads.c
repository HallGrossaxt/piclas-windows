/* Force a single-threaded BLAS at startup (Windows / MSYS2 only).
 *
 * WHY: MSYS2's OpenBLAS -- which the Windows PETSc and PICLas' own HDG Fortran both link --
 * is built multithreaded. For BLAS-1 calls on modest vectors it forks and joins a thread team
 * per call, costing a *fixed* ~50 us regardless of vector length. PETSc calls BLASaxpy ~110k
 * times in a single run of the benchmark PIC case, on vectors just above the threshold for
 * going parallel, so the synchronisation dwarfs the arithmetic:
 *
 *     VecAXPY, 1 rank   threaded     6.03 s   575 Mflop/s   (54.7 us/call)
 *                       1 thread     0.43 s  7885 Mflop/s   ( 4.0 us/call)
 *
 * That was the whole of a 1.35x "Windows is slower than Linux" gap that had been attributed to
 * MinGW codegen, the Win64 ABI, huge pages and the memory subsystem in turn. Linux only looked
 * better here because Ubuntu's reference netlib BLAS is single-threaded.
 *
 * A threaded BLAS is wrong for PICLas in general, not just in that one case: PICLas is
 * MPI-parallel, so every rank spawning its own thread team oversubscribes the machine, and the
 * matrices it hands to BLAS are small (the HDG MatVec is 4x4). One thread per rank is the
 * standard configuration for an MPI code.
 *
 * WHICH KNOB: MSYS2's OpenBLAS is built with the **OpenMP** threading backend -- libopenblas.dll
 * imports libgomp-1.dll. That matters, because an OpenMP-backend OpenBLAS **ignores both
 * OPENBLAS_NUM_THREADS and openblas_set_num_threads()**; the thread count comes from OpenMP.
 * Measured on the 1-rank PIC case, changing one variable at a time:
 *
 *     OPENBLAS_NUM_THREADS=1   37.54 s   VecAXPY  570 Mflop/s   <- no effect
 *     OMP_NUM_THREADS=1        27.97 s   VecAXPY 7530 Mflop/s   <- this is the one
 *
 * So the call that actually does something is omp_set_num_threads(1). openblas_set_num_threads
 * is still attempted afterwards, to cover a pthread-backend OpenBLAS on some other machine.
 *
 * HOW: resolved at runtime rather than linked. Both libraries are already mapped by the time
 * this runs, so GetModuleHandle/GetProcAddress finds the entry points with no link-time
 * dependency -- the call simply does nothing if neither library is present. Same approach the
 * CUDA loader uses for libpiclasGPU.
 *
 * An explicit OMP_NUM_THREADS (or OPENBLAS_NUM_THREADS) in the environment always wins, so this
 * can be overridden without a rebuild.
 *
 * Non-Windows builds are a deliberate no-op: distro BLAS packages are single-threaded by
 * default, and adding a dlfcn dependency to the Linux build buys nothing. Set OMP_NUM_THREADS=1
 * there if you link a threaded OpenBLAS yourself.
 *
 * Returns 1 if a thread count was set, 0 otherwise (nothing found, or user override present).
 */

#include <stdlib.h>

typedef void (*piclas_set_num_threads_t)(int);

#if defined(_WIN32)

#include <windows.h>

static int piclas_env_is_set(const char *name)
{
  const char *v = getenv(name);
  return (v != NULL && v[0] != '\0');
}

int piclas_set_blas_threads_serial(void)
{
  HMODULE hMod;
  piclas_set_num_threads_t setThreads;
  int didSet = 0;

  /* An explicit user setting takes precedence -- do not override it. */
  if (piclas_env_is_set("OMP_NUM_THREADS"))      return 0;
  if (piclas_env_is_set("OPENBLAS_NUM_THREADS")) return 0;

  /* Primary: the OpenMP runtime. This is what MSYS2's OpenBLAS actually obeys. */
  hMod = GetModuleHandleA("libgomp-1.dll");
  if (hMod == NULL) hMod = GetModuleHandleA("libgomp");
  if (hMod != NULL) {
    setThreads = (piclas_set_num_threads_t)(void (*)(void))
                 GetProcAddress(hMod, "omp_set_num_threads");
    if (setThreads != NULL) { setThreads(1); didSet = 1; }
  }

  /* Secondary: a pthread-backend OpenBLAS, which ignores OpenMP and needs its own call. */
  hMod = GetModuleHandleA("libopenblas.dll");
  if (hMod == NULL) hMod = GetModuleHandleA("libopenblas");
  if (hMod != NULL) {
    setThreads = (piclas_set_num_threads_t)(void (*)(void))
                 GetProcAddress(hMod, "openblas_set_num_threads");
    if (setThreads != NULL) { setThreads(1); didSet = 1; }
  }

  return didSet;
}

#else

int piclas_set_blas_threads_serial(void)
{
  return 0;
}

#endif
