// =========================================================================
// PICLas GPU acceleration — particle position push kernel
// =========================================================================
// CUDA kernel that advances particle positions by one time step:
//
//   x  += vx * dt
//   y  += vy * dt
//   z  += vz * dt
//
// Memory layout mirrors the Fortran array PartState(1:6, 1:N), which is
// stored column-major (first index varies fastest in memory):
//
//   C index:  iPart*6 + 0 → PartState(1, iPart+1) = x
//             iPart*6 + 1 → PartState(2, iPart+1) = y
//             iPart*6 + 2 → PartState(3, iPart+1) = z
//             iPart*6 + 3 → PartState(4, iPart+1) = vx
//             iPart*6 + 4 → PartState(5, iPart+1) = vy
//             iPart*6 + 5 → PartState(6, iPart+1) = vz
//
// Each CUDA thread handles exactly one particle.
// =========================================================================
#include <cuda_runtime.h>

// ---------------------------------------------------------------------------
// Kernel: particle_push_kernel
// ---------------------------------------------------------------------------
__global__ void particle_push_kernel(double * __restrict__ PartState,
                                     const int * __restrict__ isActive,
                                     int nPart, double dt)
{
    int iPart = blockIdx.x * blockDim.x + threadIdx.x;
    if (iPart >= nPart)        return;
    if (!isActive[iPart])      return;

    const int base = iPart * 6;
    PartState[base + 0] += PartState[base + 3] * dt;  // x  += vx * dt
    PartState[base + 1] += PartState[base + 4] * dt;  // y  += vy * dt
    PartState[base + 2] += PartState[base + 5] * dt;  // z  += vz * dt
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
// ---------------------------------------------------------------------------
void launch_particle_push(double *d_PartState, const int *d_isActive,
                          int nPart, double dt)
{
    const int blockSize = 256;
    const int gridSize  = (nPart + blockSize - 1) / blockSize;
    dim3 grid(gridSize, 1, 1);
    dim3 block(blockSize, 1, 1);
    void *args[] = {
        (void*)&d_PartState,
        (void*)&d_isActive,
        (void*)&nPart,
        (void*)&dt
    };
    cudaLaunchKernel((const void*)particle_push_kernel, grid, block, args, 0, nullptr);
}
