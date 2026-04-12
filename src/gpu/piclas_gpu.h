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

/* Initialize CUDA device 0, print device info. */
PICLAS_GPU_API void piclas_gpu_init(void);

/* Release all device resources and reset the device. */
PICLAS_GPU_API void piclas_gpu_finalize(void);

/* Allocate device-side PartState and isActive buffers for nMaxPart particles.
   Must be called once after piclas_gpu_init(). */
PICLAS_GPU_API void piclas_gpu_alloc_buffers(int nMaxPart);

/* Free device-side buffers. */
PICLAS_GPU_API void piclas_gpu_free_buffers(void);

/* Batch particle position push: pos += vel * dt for every active particle.
 *
 *  PartState[6 * nPart]  — Fortran column-major layout:
 *                            PartState[iPart*6 + 0..2] = x,y,z
 *                            PartState[iPart*6 + 3..5] = vx,vy,vz
 *  isActive[nPart]       — 1 = particle inside domain, 0 = empty slot
 *  nPart                 — PDM%ParticleVecLength (highest occupied index)
 *  dt                    — constant time step
 */
PICLAS_GPU_API void piclas_gpu_push_particles(double *PartState, int *isActive,
                                              int nPart, double dt);

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
 * RK_a                   — RK_a(iStage); ignored when isStage1==1
 * b_dt                   — RK_b(iStage) * dt
 */
PICLAS_GPU_API void piclas_gpu_lserk_stage(double *PartState, double *Pt_temp,
                                           double *Pt,
                                           int *isActive, int *isPush,
                                           int *isNewPart,
                                           int nPart, int isStage1,
                                           double RK_a, double b_dt);

#ifdef __cplusplus
}
#endif

#endif /* PICLAS_GPU_H */
