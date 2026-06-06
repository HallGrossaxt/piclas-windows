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
#include <climits>
#ifdef _WIN32
#  include <windows.h>   // GlobalMemoryStatusEx
#else
#  include <unistd.h>    // sysconf
#endif

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
static int    *d_dtFracPush = nullptr;   // [g_nMaxPart]     — 1=fresh surface-flux particle (DSMC push)
static double *d_dtFracRand = nullptr;   // [g_nMaxPart]     — per-particle dt scaling (1.0 for non-fresh)
static int     g_nMaxPart   = 0;

// ---------------------------------------------------------------------------
// Device-binding state (set by piclas_gpu_init in gpu_init.cu). Used to give
// each MPI rank a fair, non-overlapping slice of VRAM so that N co-resident
// ranks cannot oversubscribe a single GPU (the §16.18 regression OOM).
// ---------------------------------------------------------------------------
int g_ranksPerGPU = 1;   // ranks sharing the bound device (>= 1)
int g_gpuDeviceId = 0;   // CUDA device index this rank is bound to

// Forward declarations: kernel launchers
extern void launch_particle_push(double *d_PartState, const int *d_isActive,
                                 const int *d_dtFracPush,
                                 const double *d_dtFracRand,
                                 int nPart, double dt, int symmetryOrder);
extern void launch_lserk_stage(double *d_PartState, double *d_Pt_temp,
                               const double *d_Pt, const int *d_isActive,
                               const int *d_isPush, const int *d_isNewPart,
                               int nPart, int isStage1, double RK_a, double b_dt);

// ---------------------------------------------------------------------------
// piclas_gpu_alloc_buffers
//   Allocate device-resident (cudaMalloc) buffers for up to nMaxPart particles.
//
//   §16.18: we deliberately use cudaMalloc, NOT cudaMallocManaged. Managed
//   oversubscription (paging to host RAM when VRAM is full) does not work under
//   the Windows WDDM driver, so managed buffers gave hard OOM crashes instead of
//   the promised graceful spill. With explicit cudaMalloc the buffer is sized to
//   this rank's VRAM share (capped by piclas_gpu_query_max_safe in GPU_Init) and
//   live particle counts that exceed it are streamed in chunks by the push
//   functions below.
//
//   Returns 0 on success, -1 on failure (caller falls back to the CPU push
//   instead of aborting — no hard exit here).
//
//   Footprint per particle: 15*8 + 3*4 = 132 bytes.
// ---------------------------------------------------------------------------
int piclas_gpu_alloc_buffers(int nMaxPart)
{
    g_nMaxPart = 0;
    if (nMaxPart < 1) return -1;

    // Release any previously held buffers first.
    piclas_gpu_free_buffers();

    cudaError_t e = cudaSuccess;
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_PartState, (size_t)6 * nMaxPart * sizeof(double));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_isActive,  (size_t)nMaxPart * sizeof(int));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_Pt_temp,   (size_t)6 * nMaxPart * sizeof(double));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_Pt,        (size_t)3 * nMaxPart * sizeof(double));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_isPush,    (size_t)nMaxPart * sizeof(int));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_isNewPart, (size_t)nMaxPart * sizeof(int));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_dtFracPush,(size_t)nMaxPart * sizeof(int));
    if (e == cudaSuccess) e = cudaMalloc((void**)&d_dtFracRand,(size_t)nMaxPart * sizeof(double));

    if (e != cudaSuccess) {
        fprintf(stderr, "[GPU] cudaMalloc for %d particles failed: %s — "
                "GPU buffers not allocated, caller should use the CPU push.\n",
                nMaxPart, cudaGetErrorString(e));
        // Free whatever did succeed, leave all pointers null.
        if (d_PartState) { cudaFree(d_PartState); d_PartState = nullptr; }
        if (d_isActive)  { cudaFree(d_isActive);  d_isActive  = nullptr; }
        if (d_Pt_temp)   { cudaFree(d_Pt_temp);   d_Pt_temp   = nullptr; }
        if (d_Pt)        { cudaFree(d_Pt);        d_Pt        = nullptr; }
        if (d_isPush)    { cudaFree(d_isPush);    d_isPush    = nullptr; }
        if (d_isNewPart) { cudaFree(d_isNewPart); d_isNewPart = nullptr; }
        if (d_dtFracPush){ cudaFree(d_dtFracPush);d_dtFracPush= nullptr; }
        if (d_dtFracRand){ cudaFree(d_dtFracRand);d_dtFracRand= nullptr; }
        return -1;
    }

    // Zero Pt_temp: host Pt_temp is initialised to 0 at allocation (particle_init.f90).
    // Zeroing the device copy ensures new-particle slots in stage 2+ compute
    // Pt_temp_vel = Pt - RK_a * 0 = Pt, matching the host behaviour.
    cudaMemset(d_Pt_temp, 0, (size_t)6 * nMaxPart * sizeof(double));

    g_nMaxPart = nMaxPart;

    size_t vram_free = 0, vram_total = 0;
    cudaMemGetInfo(&vram_free, &vram_total);
    double alloc_mb = (15.0 * nMaxPart * sizeof(double) +
                       3.0  * nMaxPart * sizeof(int)) / (1024.0 * 1024.0);
    printf("[GPU] Device buffers: %d particles (chunk size), %.1f MB "
           "(VRAM free now %.1f / %.1f MB) — larger live counts stream in chunks\n",
           nMaxPart, alloc_mb,
           (double)vram_free  / (1024.0 * 1024.0),
           (double)vram_total / (1024.0 * 1024.0));
    fflush(stdout);
    return 0;
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
    if (d_dtFracPush){ CUDA_CHECK(cudaFree(d_dtFracPush)); d_dtFracPush = nullptr; }
    if (d_dtFracRand){ CUDA_CHECK(cudaFree(d_dtFracRand)); d_dtFracRand = nullptr; }
    g_nMaxPart = 0;
}

// ---------------------------------------------------------------------------
// piclas_gpu_query_max_safe
//   Returns the maximum number of particles that fit in THIS rank's fair share
//   of the bound GPU's VRAM.
//
//   IMPORTANT (§16.18): the budget is VRAM-only. cudaMallocManaged host-RAM
//   spill does NOT work under the Windows WDDM driver (oversubscription needs
//   Linux or the TCC driver), so counting system RAM here over-promises and
//   leads to hard OOM. We instead partition the card:
//
//     perRankVRAM = vram_total / ranksPerGPU
//     budget      = perRankVRAM - CTX_RESERVE   (per-rank context + fragmentation)
//
//   Using vram_total (not the racy free count) makes the cap deterministic and
//   independent of the order in which co-resident ranks initialise.
//
//   Footprint per particle (6 buffers): 15*8 + 3*4 = 132 B / particle.
// ---------------------------------------------------------------------------
int piclas_gpu_query_max_safe(void)
{
    static const size_t BYTES_PER_PART = 15 * sizeof(double) + 3 * sizeof(int);
    // Per-rank reserve for the CUDA context, runtime, and allocator
    // fragmentation. The WDDM context overhead is ~1 GB/rank; we keep a
    // conservative 768 MB so the particle buffers do not crowd it out.
    static const size_t CTX_RESERVE = (size_t)768 * 1024 * 1024;

    size_t vram_free = 0, vram_total = 0;
    if (cudaMemGetInfo(&vram_free, &vram_total) != cudaSuccess)
        vram_total = 0;

    int ranks = (g_ranksPerGPU > 0) ? g_ranksPerGPU : 1;

    size_t per_rank_vram = vram_total / (size_t)ranks;
    size_t budget = (per_rank_vram > CTX_RESERVE) ? per_rank_vram - CTX_RESERVE : 0;

    // Never trust more than the currently free VRAM for this allocation.
    if (budget > vram_free) budget = vram_free;

    size_t max_p = (BYTES_PER_PART > 0) ? budget / BYTES_PER_PART : 0;
    if (max_p > (size_t)INT_MAX) max_p = (size_t)INT_MAX;

    printf("[GPU] Memory budget (dev %d, %d rank(s)/GPU): VRAM total %.1f MB, "
           "free %.1f MB, per-rank share %.1f MB -> max %zu particles\n",
           g_gpuDeviceId, ranks,
           (double)vram_total / (1024.0 * 1024.0),
           (double)vram_free  / (1024.0 * 1024.0),
           (double)budget     / (1024.0 * 1024.0),
           max_p);
    fflush(stdout);

    return (int)max_p;
}

// ---------------------------------------------------------------------------
// piclas_gpu_push_particles  —  DSMC position push (Time-Step DSMC)
//
//   Upload PartState + isActive (+ optional dtFracPush/dtFracRand) → run
//   kernel → download updated PartState.
//
//   dtFracPush[i]  : 1 = fresh surface-flux particle (pushed by random
//                    fraction of dt); 0 = use full dt.   Pass nullptr to
//                    disable the fractional-dt feature for every particle.
//   dtFracRand[i]  : per-particle dt scaling.  Caller fills 1.0 for non-
//                    fresh particles and a uniform RNG draw for fresh ones,
//                    in iPart order, so the host RNG state advances exactly
//                    as in the CPU per-particle loop.  Ignored when
//                    dtFracPush is nullptr.
//   symmetryOrder  : 0 = no axisymmetric post-rotation;
//                    2 = rotate (y, z) so y' = ±sqrt(y²+z²), z' = 0;
//                    3 = rotate (x, z) so x' =  sqrt(x²+z²), z' = 0.
// ---------------------------------------------------------------------------
void piclas_gpu_push_particles(double *PartState, int *isActive,
                               int *dtFracPush, double *dtFracRand,
                               int nPart, double dt, int symmetryOrder)
{
    if (nPart <= 0 || g_nMaxPart <= 0) return;

    const int haveFrac = (dtFracPush != nullptr && dtFracRand != nullptr) ? 1 : 0;

    // §16.18 Phase 2: stream the live particles through the fixed device buffer
    // in chunks of g_nMaxPart. Each particle's update is independent, so slicing
    // by particle index is exact. For the common case (nPart <= g_nMaxPart) this
    // is a single iteration with no overhead.
    for (int off = 0; off < nPart; off += g_nMaxPart) {
        int chunk = nPart - off;
        if (chunk > g_nMaxPart) chunk = g_nMaxPart;

        double *ps = PartState + (size_t)off * 6;
        int    *ia = isActive  + (size_t)off;

        CUDA_CHECK(cudaMemcpy(d_PartState, ps,
                              (size_t)6 * chunk * sizeof(double),
                              cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_isActive, ia,
                              (size_t)chunk * sizeof(int),
                              cudaMemcpyHostToDevice));

        const int    *d_frac_p = nullptr;
        const double *d_frac_r = nullptr;
        if (haveFrac) {
            int    *fp = dtFracPush + (size_t)off;
            double *fr = dtFracRand + (size_t)off;
            CUDA_CHECK(cudaMemcpy(d_dtFracPush, fp,
                                  (size_t)chunk * sizeof(int),
                                  cudaMemcpyHostToDevice));
            CUDA_CHECK(cudaMemcpy(d_dtFracRand, fr,
                                  (size_t)chunk * sizeof(double),
                                  cudaMemcpyHostToDevice));
            d_frac_p = d_dtFracPush;
            d_frac_r = d_dtFracRand;
        }

        launch_particle_push(d_PartState, d_isActive,
                             d_frac_p, d_frac_r,
                             chunk, dt, symmetryOrder);

        CUDA_CHECK(cudaMemcpy(ps, d_PartState,
                              (size_t)6 * chunk * sizeof(double),
                              cudaMemcpyDeviceToHost));
    }
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
                             int isLastStage, int ptTempResident,
                             double RK_a, double b_dt)
{
    if (nPart <= 0 || g_nMaxPart <= 0) return;

    // §16.18 Phase 3: Pt_temp residency. When ptTempResident is set AND the live
    // count fits in a single chunk, Pt_temp stays on the device across the RK
    // stages of this timestep: stage 1's kernel writes it, later stages read the
    // device value, and the host copy is only refreshed on the last stage. This
    // removes the per-stage Pt_temp H2D (all stages) and D2H (all but the last).
    // Correctness requires that nothing on the host modifies Pt_temp between
    // stages — true only for a single MPI rank (no inter-stage migration), which
    // the caller enforces. Multi-rank and chunked paths round-trip every stage.
    const int resident = (ptTempResident != 0) && (nPart <= g_nMaxPart);

    // §16.18 Phase 2: stream the live particles through the fixed device buffer
    // in chunks of g_nMaxPart. Each particle's RK update depends only on its own
    // PartState/Pt_temp/Pt, so per-index slicing is exact.
    for (int off = 0; off < nPart; off += g_nMaxPart) {
        int chunk = nPart - off;
        if (chunk > g_nMaxPart) chunk = g_nMaxPart;

        double *ps  = PartState + (size_t)off * 6;
        double *ptt = Pt_temp   + (size_t)off * 6;
        double *pt  = Pt        + (size_t)off * 3;
        int    *ia  = isActive  + (size_t)off;
        int    *ip  = isPush    + (size_t)off;
        int    *inp = isNewPart + (size_t)off;

        CUDA_CHECK(cudaMemcpy(d_PartState, ps,  (size_t)6 * chunk * sizeof(double), cudaMemcpyHostToDevice));
        // Pt_temp upload: skipped in the resident path (device retains it; stage 1
        // overwrites it). Always uploaded in the round-trip path.
        if (!resident)
            CUDA_CHECK(cudaMemcpy(d_Pt_temp, ptt, (size_t)6 * chunk * sizeof(double), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_Pt,        pt,  (size_t)3 * chunk * sizeof(double), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_isActive,  ia,  (size_t)chunk * sizeof(int), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_isPush,    ip,  (size_t)chunk * sizeof(int), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_isNewPart, inp, (size_t)chunk * sizeof(int), cudaMemcpyHostToDevice));

        launch_lserk_stage(d_PartState, d_Pt_temp, d_Pt,
                           d_isActive, d_isPush, d_isNewPart,
                           chunk, isStage1, RK_a, b_dt);

        // Download updated PartState every stage (host tracking/field solve need it).
        // The cudaMemcpy acts as an implicit synchronisation point.
        CUDA_CHECK(cudaMemcpy(ps,  d_PartState, (size_t)6 * chunk * sizeof(double), cudaMemcpyDeviceToHost));
        // Pt_temp download: only on the last stage in the resident path; every
        // stage in the round-trip path (keeps host in sync for MPI migration).
        if (!resident || isLastStage)
            CUDA_CHECK(cudaMemcpy(ptt, d_Pt_temp, (size_t)6 * chunk * sizeof(double), cudaMemcpyDeviceToHost));
    }
}
