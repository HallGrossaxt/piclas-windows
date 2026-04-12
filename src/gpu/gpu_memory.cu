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
static double *d_PartState  = nullptr;   // [6 * g_nMaxPart] — pos + vel
static int    *d_isActive   = nullptr;   // [g_nMaxPart]     — active mask
static double *d_Pt_temp    = nullptr;   // [6 * g_nMaxPart] — LSERK RK staging (persistent across stages)
static double *d_Pt         = nullptr;   // [3 * g_nMaxPart] — acceleration (Lorentz force), per stage
static int    *d_isPush     = nullptr;   // [g_nMaxPart]     — 1=charged particle
static int    *d_isNewPart  = nullptr;   // [g_nMaxPart]     — 1=newly inserted particle
static int     g_nMaxPart   = 0;

// Forward declarations: kernel launchers
extern void launch_particle_push(double *d_PartState, const int *d_isActive,
                                 int nPart, double dt);
extern void launch_lserk_stage(double *d_PartState, double *d_Pt_temp,
                               const double *d_Pt, const int *d_isActive,
                               const int *d_isPush, const int *d_isNewPart,
                               int nPart, int isStage1, double RK_a, double b_dt);

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

    // LSERK buffers
    CUDA_CHECK(cudaMalloc(&d_Pt_temp,
                          (size_t)6 * nMaxPart * sizeof(double)));
    CUDA_CHECK(cudaMalloc(&d_Pt,
                          (size_t)3 * nMaxPart * sizeof(double)));
    CUDA_CHECK(cudaMalloc(&d_isPush,
                          (size_t)nMaxPart * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_isNewPart,
                          (size_t)nMaxPart * sizeof(int)));

    // Zero Pt_temp: host Pt_temp is initialised to 0 at allocation (particle_init.f90).
    // Zeroing the device copy ensures new-particle slots in stage 2+ compute
    // Pt_temp_vel = Pt - RK_a * 0 = Pt, matching the host behaviour.
    CUDA_CHECK(cudaMemset(d_Pt_temp, 0, (size_t)6 * nMaxPart * sizeof(double)));

    double mb = (9.0 * nMaxPart * sizeof(double) +
                 3.0 * nMaxPart * sizeof(int)) / (1024.0 * 1024.0);
    printf("[GPU] Device buffers allocated: %d particles, %.1f MB\n",
           nMaxPart, mb);
    fflush(stdout);
}

// ---------------------------------------------------------------------------
// piclas_gpu_free_buffers
// ---------------------------------------------------------------------------
void piclas_gpu_free_buffers(void)
{
    if (d_PartState) { CUDA_CHECK(cudaFree(d_PartState));  d_PartState  = nullptr; }
    if (d_isActive)  { CUDA_CHECK(cudaFree(d_isActive));   d_isActive   = nullptr; }
    if (d_Pt_temp)   { CUDA_CHECK(cudaFree(d_Pt_temp));    d_Pt_temp    = nullptr; }
    if (d_Pt)        { CUDA_CHECK(cudaFree(d_Pt));         d_Pt         = nullptr; }
    if (d_isPush)    { CUDA_CHECK(cudaFree(d_isPush));     d_isPush     = nullptr; }
    if (d_isNewPart) { CUDA_CHECK(cudaFree(d_isNewPart));  d_isNewPart  = nullptr; }
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

// ---------------------------------------------------------------------------
// piclas_gpu_lserk_stage
//   Execute one RK stage of the LSERK4 particle push.
//
//   Upload protocol per stage:
//     H2D: PartState, Pt_temp, Pt, isActive, isPush, isNewPart
//     Kernel: updates d_PartState and d_Pt_temp in-place
//     D2H: PartState, Pt_temp
//
//   Pt_temp is round-tripped each stage to keep the host copy in sync.
//   This mirrors the Linux MPI design where Pt_temp lives on the host and
//   is communicated alongside migrating particles.  For single-node builds
//   the D2H of Pt_temp is cheap and ensures future MPI+GPU correctness.
// ---------------------------------------------------------------------------
void piclas_gpu_lserk_stage(double *PartState, double *Pt_temp,
                             double *Pt,
                             int *isActive, int *isPush, int *isNewPart,
                             int nPart, int isStage1,
                             double RK_a, double b_dt)
{
    if (nPart <= 0 || nPart > g_nMaxPart) {
        fprintf(stderr,
                "[GPU] lserk_stage: nPart=%d out of range [1,%d]\n",
                nPart, g_nMaxPart);
        return;
    }

    // Upload all per-stage inputs
    CUDA_CHECK(cudaMemcpy(d_PartState,  PartState,
                          (size_t)6 * nPart * sizeof(double),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_Pt_temp,    Pt_temp,
                          (size_t)6 * nPart * sizeof(double),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_Pt,         Pt,
                          (size_t)3 * nPart * sizeof(double),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_isActive,   isActive,
                          (size_t)nPart * sizeof(int),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_isPush,     isPush,
                          (size_t)nPart * sizeof(int),
                          cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_isNewPart,  isNewPart,
                          (size_t)nPart * sizeof(int),
                          cudaMemcpyHostToDevice));

    // Run LSERK stage kernel
    launch_lserk_stage(d_PartState, d_Pt_temp, d_Pt,
                       d_isActive, d_isPush, d_isNewPart,
                       nPart, isStage1, RK_a, b_dt);

    // Download updated PartState and Pt_temp back to host.
    // The cudaMemcpy call acts as an implicit synchronisation point.
    CUDA_CHECK(cudaMemcpy(PartState, d_PartState,
                          (size_t)6 * nPart * sizeof(double),
                          cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(Pt_temp,   d_Pt_temp,
                          (size_t)6 * nPart * sizeof(double),
                          cudaMemcpyDeviceToHost));
}
