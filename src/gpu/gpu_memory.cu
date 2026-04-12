// =========================================================================
// PICLas GPU acceleration — device memory management + push entry point
// =========================================================================
// Device-side buffers for PartState and the active-particle mask are kept as
// static module-level pointers so that Fortran does not need to manage raw
// device pointers.
// =========================================================================
#include "piclas_gpu.h"
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>

#define CUDA_CHECK(call)                                                   \
  do {                                                                     \
    cudaError_t _err = (call);                                             \
    if (_err != cudaSuccess) {                                             \
      fprintf(stderr, "[GPU] CUDA error at %s:%d — %s\n",                 \
              __FILE__, __LINE__, cudaGetErrorString(_err));               \
      exit(EXIT_FAILURE);                                                  \
    }                                                                      \
  } while (0)

// ---------------------------------------------------------------------------
// Module-level device pointers
// ---------------------------------------------------------------------------
static double *d_PartState = nullptr;   // [6 * g_nMaxPart] doubles
static int    *d_isActive  = nullptr;   // [g_nMaxPart] ints
static int     g_nMaxPart  = 0;

// Forward declaration: kernel launcher defined in particle_push.cu
extern void launch_particle_push(double *d_PartState, const int *d_isActive,
                                 int nPart, double dt);

// ---------------------------------------------------------------------------
// piclas_gpu_alloc_buffers
//   Allocate device buffers large enough for nMaxPart particles.
//   Memory footprint: 7 * nMaxPart * 8 bytes (6 doubles + 1 int rounded up).
// ---------------------------------------------------------------------------
void piclas_gpu_alloc_buffers(int nMaxPart)
{
    g_nMaxPart = nMaxPart;

    CUDA_CHECK(cudaMalloc(&d_PartState,
                          (size_t)6 * nMaxPart * sizeof(double)));
    CUDA_CHECK(cudaMalloc(&d_isActive,
                          (size_t)nMaxPart * sizeof(int)));

    double mb = (6.0 * nMaxPart * sizeof(double) +
                 1.0 * nMaxPart * sizeof(int)) / (1024.0 * 1024.0);
    printf("[GPU] Device buffers allocated: %d particles, %.1f MB\n",
           nMaxPart, mb);
    fflush(stdout);
}

// ---------------------------------------------------------------------------
// piclas_gpu_free_buffers
// ---------------------------------------------------------------------------
void piclas_gpu_free_buffers(void)
{
    if (d_PartState) { CUDA_CHECK(cudaFree(d_PartState)); d_PartState = nullptr; }
    if (d_isActive)  { CUDA_CHECK(cudaFree(d_isActive));  d_isActive  = nullptr; }
    g_nMaxPart = 0;
}

// ---------------------------------------------------------------------------
// piclas_gpu_push_particles
//   Upload PartState + isActive → run kernel → download updated PartState.
// ---------------------------------------------------------------------------
void piclas_gpu_push_particles(double *PartState, int *isActive,
                               int nPart, double dt)
{
    if (nPart <= 0 || nPart > g_nMaxPart) {
        fprintf(stderr,
                "[GPU] push_particles: nPart=%d out of range [1,%d]\n",
                nPart, g_nMaxPart);
        return;
    }

    // Upload particle data to device
    CUDA_CHECK(cudaMemcpy(d_PartState, PartState,
                          (size_t)6 * nPart * sizeof(double),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_isActive, isActive,
                          (size_t)nPart * sizeof(int),
                          cudaMemcpyHostToDevice));

    // Run CUDA kernel
    launch_particle_push(d_PartState, d_isActive, nPart, dt);

    // Download updated positions (all 6 components: pos changed, vel unchanged)
    CUDA_CHECK(cudaMemcpy(PartState, d_PartState,
                          (size_t)6 * nPart * sizeof(double),
                          cudaMemcpyDeviceToHost));
}
