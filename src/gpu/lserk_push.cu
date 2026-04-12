// =========================================================================
// PICLas GPU acceleration — LSERK4 per-stage particle push kernel
// =========================================================================
// Implements one RK stage of the Low-Storage Explicit Runge-Kutta scheme
// used in PP_TimeDiscMethod 2 (LSERK4-5, Carpenter 1994) and
// PP_TimeDiscMethod 6 (LSERK4-14, Niegemann 2012).
//
// Called from TimeStepByLSERK via GPU_LSERKStageBatch (gpu_interface.f90)
// when PICLAS_USE_GPU=1 and all eligibility conditions are met.
//
// Memory layout (Fortran column-major, 1-based Fortran ↔ 0-based C):
//   PartState[iPart*6 + 0..2] ↔ PartState(1:3, iPart+1) = x, y, z
//   PartState[iPart*6 + 3..5] ↔ PartState(4:6, iPart+1) = vx, vy, vz
//   Pt_temp  [iPart*6 + 0..2] ↔ Pt_temp(1:3,   iPart+1) = RK pos derivative
//   Pt_temp  [iPart*6 + 3..5] ↔ Pt_temp(4:6,   iPart+1) = RK vel derivative
//   Pt       [iPart*3 + 0..2] ↔ Pt(1:3,         iPart+1) = acceleration (F/m)
//
// Design principle — Pt_temp residency (from Linux MPI analysis):
//   Pt_temp is persistent on the GPU across all RK stages of a timestep.
//   Between stages, only PartState is downloaded (for host-side tracking).
//   This mirrors the Linux MPI design where Pt_temp lives on the host for
//   the full timestep and is communicated alongside migrating particles.
//   For single-node (current target), Pt_temp never needs to leave the GPU
//   within a timestep; it is uploaded once at the start and downloaded once
//   at the end to keep the host copy in sync for future MPI+GPU support.
// =========================================================================
#include <cuda_runtime.h>

// ---------------------------------------------------------------------------
// lserk_stage_kernel
//
// One thread per particle.  Handles four cases:
//   isStage1=1, isNewPart=0  →  stage-1 formula (set Pt_temp, advance)
//   isStage1=0, isNewPart=0  →  stage-N formula (accumulate Pt_temp, advance)
//   isStage1=0, isNewPart=1  →  new particle in stage N:
//                                 pos derivative set, position NOP
//                                 vel derivative: Pt (Fortran Pt_temp was 0)
//   isStage1=1, isNewPart=1  →  treated as plain stage-1 (isNewPart irrelevant)
//
// isPush: 0 for neutral particles — position is advanced but velocity is not.
// ---------------------------------------------------------------------------
__global__ void lserk_stage_kernel(
    double * __restrict__ PartState,      // [6 * nMaxPart], updated in-place
    double * __restrict__ Pt_temp,        // [6 * nMaxPart], updated in-place
    const double * __restrict__ Pt,       // [3 * nMaxPart], read-only acceleration
    const int * __restrict__ isActive,    // 1=inside domain, 0=empty slot
    const int * __restrict__ isPush,      // 1=charged (vel pushed), 0=neutral
    const int * __restrict__ isNewPart,   // 1=newly inserted particle
    int    nPart,
    int    isStage1,   // 1 for iStage==1, 0 otherwise
    double RK_a,       // RK_a(iStage); ignored when isStage1==1
    double b_dt)       // RK_b(iStage) * dt
{
    const int iPart = blockIdx.x * blockDim.x + threadIdx.x;
    if (iPart >= nPart)   return;
    if (!isActive[iPart]) return;

    const int b6 = iPart * 6;
    const int b3 = iPart * 3;

    const int s1   = isStage1;
    const int newp = isNewPart[iPart];

    // -----------------------------------------------------------------------
    // Position update
    // -----------------------------------------------------------------------
    if (s1) {
        // Stage 1 — set Pt_temp_pos = vel, then advance position
        Pt_temp[b6+0] = PartState[b6+3];
        Pt_temp[b6+1] = PartState[b6+4];
        Pt_temp[b6+2] = PartState[b6+5];
        PartState[b6+0] += PartState[b6+3] * b_dt;
        PartState[b6+1] += PartState[b6+4] * b_dt;
        PartState[b6+2] += PartState[b6+5] * b_dt;
    } else if (newp) {
        // New particle in stage N (iStage >= 2):
        //   Fortran: Pt_temp(1:3) = PartState(4:6)   [set]
        //            PartState(1:3) = PartState(1:3)  [NOP — not advanced]
        Pt_temp[b6+0] = PartState[b6+3];
        Pt_temp[b6+1] = PartState[b6+4];
        Pt_temp[b6+2] = PartState[b6+5];
        // position unchanged (NOP)
    } else {
        // Stage N (existing particle):
        //   Pt_temp_pos = vel - RK_a * Pt_temp_pos
        //   pos += Pt_temp_pos * b_dt
        double ptx = PartState[b6+3] - RK_a * Pt_temp[b6+0];
        double pty = PartState[b6+4] - RK_a * Pt_temp[b6+1];
        double ptz = PartState[b6+5] - RK_a * Pt_temp[b6+2];
        Pt_temp[b6+0] = ptx;
        Pt_temp[b6+1] = pty;
        Pt_temp[b6+2] = ptz;
        PartState[b6+0] += ptx * b_dt;
        PartState[b6+1] += pty * b_dt;
        PartState[b6+2] += ptz * b_dt;
    }

    // -----------------------------------------------------------------------
    // Velocity update (charged particles only)
    // -----------------------------------------------------------------------
    if (!isPush[iPart]) return;

    if (s1 || newp) {
        // Stage 1 OR new particle in stage N:
        //   Fortran stage-1:      Pt_temp_vel = Pt
        //   Fortran new in stageN: Pt_temp_vel = Pt - RK_a * 0 = Pt
        //   (host Pt_temp was initialised to 0 at allocation — GPU mirrors this)
        Pt_temp[b6+3] = Pt[b3+0];
        Pt_temp[b6+4] = Pt[b3+1];
        Pt_temp[b6+5] = Pt[b3+2];
        PartState[b6+3] += Pt[b3+0] * b_dt;
        PartState[b6+4] += Pt[b3+1] * b_dt;
        PartState[b6+5] += Pt[b3+2] * b_dt;
    } else {
        // Stage N (existing charged particle):
        //   Pt_temp_vel = Pt - RK_a * Pt_temp_vel
        //   vel += Pt_temp_vel * b_dt
        double pvx = Pt[b3+0] - RK_a * Pt_temp[b6+3];
        double pvy = Pt[b3+1] - RK_a * Pt_temp[b6+4];
        double pvz = Pt[b3+2] - RK_a * Pt_temp[b6+5];
        Pt_temp[b6+3] = pvx;
        Pt_temp[b6+4] = pvy;
        Pt_temp[b6+5] = pvz;
        PartState[b6+3] += pvx * b_dt;
        PartState[b6+4] += pvy * b_dt;
        PartState[b6+5] += pvz * b_dt;
    }
}

// ---------------------------------------------------------------------------
// launch_lserk_stage  —  called from gpu_memory.cu
// ---------------------------------------------------------------------------
void launch_lserk_stage(double *d_PartState, double *d_Pt_temp,
                        const double *d_Pt, const int *d_isActive,
                        const int *d_isPush, const int *d_isNewPart,
                        int nPart, int isStage1, double RK_a, double b_dt)
{
    const int blockSize = 256;
    const int gridSize  = (nPart + blockSize - 1) / blockSize;
    dim3 grid(gridSize, 1, 1);
    dim3 block(blockSize, 1, 1);
    void *args[] = {
        (void*)&d_PartState,
        (void*)&d_Pt_temp,
        (void*)&d_Pt,
        (void*)&d_isActive,
        (void*)&d_isPush,
        (void*)&d_isNewPart,
        (void*)&nPart,
        (void*)&isStage1,
        (void*)&RK_a,
        (void*)&b_dt
    };
    // Use cudaLaunchKernel() instead of <<<>>> syntax to avoid the nvcc-generated
    // host stub with MSVC thread-safe static init (_Init_thread_header/footer),
    // which cannot be satisfied by MinGW's linker (§14.5 Challenge 11).
    cudaLaunchKernel((const void*)lserk_stage_kernel, grid, block, args, 0, nullptr);
}
