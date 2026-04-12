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
// piclas_gpu_init
//   Select device 0, print device properties.
// ---------------------------------------------------------------------------
void piclas_gpu_init(void)
{
    int devCount = 0;
    printf("[GPU] Querying CUDA device count ...\n"); fflush(stdout);
    CUDA_CHECK(cudaGetDeviceCount(&devCount));
    if (devCount == 0) {
        fprintf(stderr, "[GPU] No CUDA-capable devices found!\n");
        exit(EXIT_FAILURE);
    }

    CUDA_CHECK(cudaSetDevice(0));

    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));

    printf("[GPU] -------------------------------------------------------\n");
    printf("[GPU] CUDA device 0 : %s\n", prop.name);
    printf("[GPU]   Compute capability : %d.%d\n", prop.major, prop.minor);
    printf("[GPU]   Global memory      : %.1f GB\n",
           (double)prop.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));
    printf("[GPU]   Multiprocessors    : %d x SM\n", prop.multiProcessorCount);
    printf("[GPU]   Max threads/block  : %d\n", prop.maxThreadsPerBlock);
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
