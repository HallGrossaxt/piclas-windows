/* =========================================================================
 * PICLas GPU acceleration — C interface header
 * =========================================================================
 * All functions are callable from both C/CUDA translation units and from
 * Fortran via ISO_C_BINDING (see gpu_interface.f90).
 * ========================================================================= */
#ifndef PICLAS_GPU_H
#define PICLAS_GPU_H

/* Export from libpiclasGPU.dll when building the GPU shared library.
 * gpu_loader.c (in libpiclas.dll) resolves these via GetProcAddress. */
#if defined(PICLAS_BUILDING_GPU_DLL)
#  define PICLAS_GPU_API __declspec(dllexport)
#else
#  define PICLAS_GPU_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Initialize CUDA: bind this MPI rank to a GPU by its node-local rank, print
   device info. localRank/localSize are the rank and size on the shared-memory
   compute node (myComputeNodeRank / nComputeNodeProcessors); pass 0/1 for a
   serial build. The bound device is localRank % deviceCount, and the number of
   ranks sharing that device (ranksPerGPU) is used to partition the VRAM budget
   in piclas_gpu_query_max_safe(). */
PICLAS_GPU_API void piclas_gpu_init(int localRank, int localSize);

/* Release all device resources and reset the device. */
PICLAS_GPU_API void piclas_gpu_finalize(void);

/* Allocate device-side buffers (cudaMalloc) for nMaxPart particles.
   Must be called once after piclas_gpu_init().
   Returns 0 on success, -1 on allocation failure (caller should fall back to
   the CPU push rather than abort). */
PICLAS_GPU_API int piclas_gpu_alloc_buffers(int nMaxPart);

/* Free device-side buffers. */
PICLAS_GPU_API void piclas_gpu_free_buffers(void);

/* Query the maximum number of particles that can be safely allocated in this
   rank's fair share of the bound GPU's VRAM.  The budget is VRAM-only
   (managed-memory host-RAM spill does NOT work under the Windows WDDM driver),
   partitioned by ranksPerGPU and reduced by a per-rank CUDA-context reserve.
   Returns 0 on error or when no usable share remains (caller must handle
   gracefully, e.g. fall back to the CPU push). */
PICLAS_GPU_API int piclas_gpu_query_max_safe(void);

/* Batch particle position push: pos += vel * dt for every active particle.
 *
 *  PartState[6 * nPart]  — Fortran column-major layout:
 *                            PartState[iPart*6 + 0..2] = x,y,z
 *                            PartState[iPart*6 + 3..5] = vx,vy,vz
 *  isActive[nPart]       — 1 = particle inside domain, 0 = empty slot
 *  dtFracPush[nPart]     — 1 = fresh surface-flux particle (push by random
 *                          fraction of dt); 0 = full dt.  Pass NULL to
 *                          disable the fractional-dt path entirely.
 *  dtFracRand[nPart]     — per-particle dt scaling (1.0 for non-fresh
 *                          particles; uniform [0,1] RNG draw for fresh
 *                          ones, generated host-side in iPart order so the
 *                          host RNG state stays synchronised with the CPU
 *                          per-particle loop).  Ignored when dtFracPush is
 *                          NULL.
 *  nPart                 — PDM%ParticleVecLength (highest occupied index)
 *  dt                    — constant time step
 *  symmetryOrder         — 0 = none, 2 = axisymmetric (rotate y,z),
 *                          3 = axisymmetric (rotate x,z).
 */
PICLAS_GPU_API void piclas_gpu_push_particles(double *PartState, int *isActive,
                                              int *dtFracPush, double *dtFracRand,
                                              int nPart, double dt,
                                              int symmetryOrder);

/* LSERK4 per-stage particle push (PP_TimeDiscMethod 2 and 6).
 *
 * Call once per RK stage from TimeStepByLSERK.
 *
 * Upload protocol (per stage):
 *   PartState[6*nPart]   — current positions+velocities (H2D each stage;
 *                          tracking may have modified positions between stages)
 *   Pt_temp[6*nPart]     — RK staging array (H2D + D2H each stage to keep
 *                          host copy in sync for future MPI+GPU support)
 *   Pt[3*nPart]          — particle acceleration from Lorentz force (H2D;
 *                          recomputed by CalcPartRHS each stage)
 *   isActive[nPart]      — active-particle mask (H2D; tracking may deactivate)
 *   isPush[nPart]        — 1=charged particle (vel pushed), 0=neutral (H2D)
 *   isNewPart[nPart]     — 1=newly inserted particle needing stage-1 treatment
 *
 * isStage1               — pass 1 for iStage==1, 0 for subsequent stages
 * isLastStage            — pass 1 for iStage==nRKStages, 0 otherwise
 * ptTempResident         — 1 = keep Pt_temp device-resident across the RK stages
 *                          of this timestep (skip its per-stage H2D; download it
 *                          only on the last stage). Safe ONLY when no particle
 *                          migrates between stages, i.e. a single MPI rank — the
 *                          caller passes 1 only for nProcessors==1. With multiple
 *                          ranks, or when the live count exceeds the device buffer
 *                          (chunked), Pt_temp is round-tripped every stage as before.
 * RK_a                   — RK_a(iStage); ignored when isStage1==1
 * b_dt                   — RK_b(iStage) * dt
 */
PICLAS_GPU_API void piclas_gpu_lserk_stage(double *PartState, double *Pt_temp,
                                           double *Pt,
                                           int *isActive, int *isPush,
                                           int *isNewPart,
                                           int nPart, int isStage1,
                                           int isLastStage, int ptTempResident,
                                           double RK_a, double b_dt);

#ifdef __cplusplus
}
#endif

#endif /* PICLAS_GPU_H */
