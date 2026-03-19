/* =========================================================================
 * PICLas GPU acceleration — C interface header
 * =========================================================================
 * All functions are callable from both C/CUDA translation units and from
 * Fortran via ISO_C_BINDING (see gpu_interface.f90).
 * ========================================================================= */
#ifndef PICLAS_GPU_H
#define PICLAS_GPU_H

#ifdef __cplusplus
extern "C" {
#endif

/* Initialize CUDA device 0, print device info. */
void piclas_gpu_init(void);

/* Release all device resources and reset the device. */
void piclas_gpu_finalize(void);

/* Allocate device-side PartState and isActive buffers for nMaxPart particles.
   Must be called once after piclas_gpu_init(). */
void piclas_gpu_alloc_buffers(int nMaxPart);

/* Free device-side buffers. */
void piclas_gpu_free_buffers(void);

/* Batch particle position push: pos += vel * dt for every active particle.
 *
 *  PartState[6 * nPart]  — Fortran column-major layout:
 *                            PartState[iPart*6 + 0..2] = x,y,z
 *                            PartState[iPart*6 + 3..5] = vx,vy,vz
 *  isActive[nPart]       — 1 = particle inside domain, 0 = empty slot
 *  nPart                 — PDM%ParticleVecLength (highest occupied index)
 *  dt                    — constant time step
 */
void piclas_gpu_push_particles(double *PartState, int *isActive,
                               int nPart, double dt);

#ifdef __cplusplus
}
#endif

#endif /* PICLAS_GPU_H */
