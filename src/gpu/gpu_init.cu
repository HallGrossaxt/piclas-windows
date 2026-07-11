// =========================================================================
// PICLas GPU acceleration — device initialisation and finalisation
// =========================================================================
#include "piclas_gpu.h"
#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>

// ---------------------------------------------------------------------------
// Helper macro: abort on CUDA error
// ---------------------------------------------------------------------------
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
// Shared device-binding state (definitions live in gpu_memory.cu, which uses
// them to partition the VRAM budget by the number of ranks sharing a GPU).
// ---------------------------------------------------------------------------
extern int g_ranksPerGPU;   // ranks sharing the bound device (>= 1)
extern int g_gpuDeviceId;   // CUDA device index this rank is bound to

// ---------------------------------------------------------------------------
// piclas_gpu_init
//   Bind this MPI rank to a GPU by its node-local rank and print device info.
//
//   On a node with deviceCount GPUs and localSize ranks, rank localRank is
//   bound to device (localRank % deviceCount).  ranksPerGPU is the number of
//   local ranks that land on the same device; it is used downstream to give
//   each rank a fair, non-overlapping slice of VRAM so that N co-resident
//   ranks cannot collectively oversubscribe a single card (the §16.18 OOM).
//
//   For genuine many-ranks-per-GPU runs, prefer NVIDIA MPS so all ranks share
//   one CUDA context and avoid the ~1 GB/rank context overhead.
// ---------------------------------------------------------------------------
void piclas_gpu_init(int localRank, int localSize)
{
    int devCount = 0;
    printf("[GPU] Querying CUDA device count ...\n"); fflush(stdout);
    CUDA_CHECK(cudaGetDeviceCount(&devCount));
    if (devCount == 0) {
        fprintf(stderr, "[GPU] No CUDA-capable devices found!\n");
        exit(EXIT_FAILURE);
    }

    if (localSize < 1) localSize = 1;
    if (localRank < 0) localRank = 0;

    const int deviceId = localRank % devCount;

    // Number of local ranks that map to this same device.
    int ranksPerGPU = localSize / devCount;
    if (localSize % devCount > deviceId) ranksPerGPU += 1;
    if (ranksPerGPU < 1) ranksPerGPU = 1;

    CUDA_CHECK(cudaSetDevice(deviceId));

    g_gpuDeviceId = deviceId;
    g_ranksPerGPU = ranksPerGPU;

    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, deviceId));

    printf("[GPU] -------------------------------------------------------\n");
    printf("[GPU] Rank binding      : localRank %d / %d  ->  device %d of %d\n",
           localRank, localSize, deviceId, devCount);
    printf("[GPU] Ranks sharing dev : %d\n", ranksPerGPU);
    printf("[GPU] CUDA device %d : %s\n", deviceId, prop.name);
    printf("[GPU]   Compute capability : %d.%d\n", prop.major, prop.minor);
    printf("[GPU]   Global memory      : %.1f GB\n",
           (double)prop.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));
    printf("[GPU]   Multiprocessors    : %d x SM\n", prop.multiProcessorCount);
    printf("[GPU]   Max threads/block  : %d\n", prop.maxThreadsPerBlock);
    if (ranksPerGPU > 1)
        printf("[GPU]   NOTE: %d ranks share this GPU; VRAM is partitioned per rank. "
               "Consider NVIDIA MPS for many-rank single-GPU runs.\n", ranksPerGPU);
    printf("[GPU] PICLas GPU acceleration ENABLED.\n");
    printf("[GPU] -------------------------------------------------------\n");
    fflush(stdout);
}

// ---------------------------------------------------------------------------
// piclas_gpu_finalize
//   Reset the device (frees all CUDA allocations and contexts).
// ---------------------------------------------------------------------------
void piclas_gpu_finalize(void)
{
    CUDA_CHECK(cudaDeviceReset());
    printf("[GPU] CUDA device reset — GPU acceleration finalised.\n");
    fflush(stdout);
}
