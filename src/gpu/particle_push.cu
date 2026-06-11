// =========================================================================
// PICLas GPU acceleration — particle position push kernel (DSMC)
// =========================================================================
// CUDA kernel that advances particle positions by one time step.
//
// Supports three orthogonal features required by the DSMC time stepper:
//
//   1) Constant-dt push (default):
//        x += vx * dt;  y += vy * dt;  z += vz * dt;
//
//   2) Surface-flux fractional-dt push (per-particle):
//        if (dtFracPush[i])  scale = dtFracRand[i]  else  scale = 1
//        x += vx * dt * scale  (etc.)
//      The host generates dtFracRand[i] in iPart order BEFORE the kernel
//      launch (one RANDOM_NUMBER per fresh particle), matching the CPU
//      RNG-consumption order so results are reproducible.  Non-fresh
//      particles get dtFracRand[i] = 1.0 from the host.
//
//   3) Axisymmetric post-rotation (Symmetry%Order = 2 or 3):
//        After the position update, rotate the (y, z) [Order 2] or
//        (x, z) [Order 3] components so the radial coordinate is
//        positive and the off-plane component is zero. Velocities are
//        rotated by the same angle (preserving sign convention).
//        Particles landing on the axis (|r| < eps) keep their original
//        velocities — division by zero is avoided.
//
// Memory layout (Fortran column-major, 1-based ↔ 0-based C):
//   PartState[iPart*6 + 0..2] ↔ PartState(1:3, iPart+1) = x, y, z
//   PartState[iPart*6 + 3..5] ↔ PartState(4:6, iPart+1) = vx, vy, vz
// =========================================================================
#include <cuda_runtime.h>
#include <math.h>

// On-axis tolerance for the axisymmetric rotation.  Below this radius we
// leave the velocity untouched (CPU code would divide by ~0 and emit NaN;
// returning the input is the physically reasonable answer for an on-axis
// particle, since any rotation maps it to itself).
__device__ static const double SYMM_AXIS_EPS = 1e-300;

// ---------------------------------------------------------------------------
// Kernel: particle_push_kernel
//   symmetryOrder == 0 → no axisymmetric rotation
//   symmetryOrder == 2 → rotate (y, z)
//   symmetryOrder == 3 → rotate (x, z)
// ---------------------------------------------------------------------------
__global__ void particle_push_kernel(double * __restrict__ PartState,
                                     const int    * __restrict__ isActive,
                                     const int    * __restrict__ dtFracPush,
                                     const double * __restrict__ dtFracRand,
                                     int nPart, double dt,
                                     int symmetryOrder)
{
    int iPart = blockIdx.x * blockDim.x + threadIdx.x;
    if (iPart >= nPart)   return;
    if (!isActive[iPart]) return;

    const int base = iPart * 6;

    // ---- 1) Position update with per-particle dt scaling ----
    // dtFracRand[i] is 1.0 for non-fresh particles (host-filled);
    // for fresh particles it carries the host-generated uniform random number.
    const double scale = (dtFracPush != nullptr && dtFracPush[iPart])
                         ? dtFracRand[iPart] : 1.0;
    const double dtEff = dt * scale;

    double x = PartState[base + 0];
    double y = PartState[base + 1];
    double z = PartState[base + 2];
    double vx = PartState[base + 3];
    double vy = PartState[base + 4];
    double vz = PartState[base + 5];

    x += vx * dtEff;
    y += vy * dtEff;
    z += vz * dtEff;

    // ---- 2) Axisymmetric post-rotation (mirrors CalcPartSymmetryPos) ----
    if (symmetryOrder == 2) {
        // Order 2: rotate (y, z) so that y' = ±sqrt(y² + z²) (sign of y), z' = 0
        double r = sqrt(y*y + z*z);
        if (r > SYMM_AXIS_EPS) {
            double newY = (y < 0.0) ? -r : r;
            // Vy' = ( Vy*y + Vz*z) / newY
            // Vz' = (-Vy*z + Vz*y) / newY
            double newVy = ( vy*y + vz*z) / newY;
            double newVz = (-vy*z + vz*y) / newY;
            y  = newY;
            z  = 0.0;
            vy = newVy;
            vz = newVz;
        } else {
            // On axis: position collapses to (x, 0, 0); velocity left alone.
            y = 0.0;
            z = 0.0;
        }
    } else if (symmetryOrder == 3) {
        // Order 3: rotate (x, z) so that x' = +sqrt(x² + z²), z' = 0
        double r = sqrt(x*x + z*z);
        if (r > SYMM_AXIS_EPS) {
            double newX  = r;
            double newVx = ( vx*x + vz*z) / newX;
            double newVz = (-vx*z + vz*x) / newX;
            x  = newX;
            z  = 0.0;
            vx = newVx;
            vz = newVz;
            // y is also zeroed per CPU code (line 2283 of particle_tools.f90)
            y  = 0.0;
        } else {
            x = 0.0;
            y = 0.0;
            z = 0.0;
        }
    }
    // symmetryOrder == 0 → no rotation, fall through.

    PartState[base + 0] = x;
    PartState[base + 1] = y;
    PartState[base + 2] = z;
    PartState[base + 3] = vx;
    PartState[base + 4] = vy;
    PartState[base + 5] = vz;
}

// ---------------------------------------------------------------------------
// launch_particle_push
//   Called from gpu_memory.cu.  cudaMemcpy after the launch acts as an
//   implicit synchronisation point, so no extra cudaDeviceSynchronize needed.
//
//   Uses cudaLaunchKernel() instead of <<<>>> syntax to avoid the nvcc-generated
//   host stub that contains a function-local static with MSVC thread-safe init
//   (_Init_thread_header/_Init_thread_footer/_Init_thread_epoch), which cannot
//   be satisfied by MinGW's linker.
//
//   dtFracPush, dtFracRand may be device pointers; when both are null the
//   kernel reverts to the plain constant-dt push for every particle.
// ---------------------------------------------------------------------------
void launch_particle_push(double *d_PartState, const int *d_isActive,
                          const int *d_dtFracPush, const double *d_dtFracRand,
                          int nPart, double dt, int symmetryOrder)
{
    const int blockSize = 256;
    const int gridSize  = (nPart + blockSize - 1) / blockSize;
    dim3 grid(gridSize, 1, 1);
    dim3 block(blockSize, 1, 1);
    void *args[] = {
        (void*)&d_PartState,
        (void*)&d_isActive,
        (void*)&d_dtFracPush,
        (void*)&d_dtFracRand,
        (void*)&nPart,
        (void*)&dt,
        (void*)&symmetryOrder
    };
    cudaLaunchKernel((const void*)particle_push_kernel, grid, block, args, 0, nullptr);
}
