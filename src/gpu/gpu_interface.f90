!=================================================================================================================================
! PICLas GPU acceleration — Fortran ISO_C_BINDING interface to CUDA C functions
! and high-level Fortran wrappers called from time-stepping modules.
!=================================================================================================================================
MODULE MOD_GPU_Interface
USE ISO_C_BINDING
USE MOD_GPU_Vars
IMPLICIT NONE
PRIVATE

!=================================================================================================================================
! Low-level BIND(C) interface to the CUDA C functions in src/gpu/ (*.cu files)
!=================================================================================================================================
INTERFACE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! Load libpiclasGPU.dll explicitly via LoadLibrary (Windows only).
  ! Must be called before any other GPU function.  By calling it from GPU_Init
  ! (after main() has started), CUDA initialises outside the DLL loader lock,
  ! preventing the Windows loader deadlock that hangs the process before main().
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_load_library() BIND(C, NAME='piclas_gpu_load_library')
  END SUBROUTINE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! Initialize CUDA device 0 and print device info.
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_init() BIND(C, NAME='piclas_gpu_init')
  END SUBROUTINE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! Release all device resources and reset the device.
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_finalize() BIND(C, NAME='piclas_gpu_finalize')
  END SUBROUTINE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! Allocate device buffers for up to nMaxPart particles.
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_alloc_buffers(nMaxPart) BIND(C, NAME='piclas_gpu_alloc_buffers')
    IMPORT :: C_INT
    INTEGER(C_INT), VALUE, INTENT(IN) :: nMaxPart
  END SUBROUTINE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! Free device buffers.
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_free_buffers() BIND(C, NAME='piclas_gpu_free_buffers')
  END SUBROUTINE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! Batch position push: pos += vel * dt for all active particles.
  !   PartState(*) — Fortran PartState(1:6, 1:nPart) passed as flat C array
  !   isActive(*)  — INTEGER(C_INT) mask (1 = active, 0 = empty slot)
  !   nPart        — PDM%ParticleVecLength
  !   dt           — constant time step
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_push_particles(PartState, isActive, nPart, dt) &
      BIND(C, NAME='piclas_gpu_push_particles')
    IMPORT :: C_DOUBLE, C_INT
    REAL(C_DOUBLE), INTENT(INOUT) :: PartState(*)
    INTEGER(C_INT), INTENT(IN)    :: isActive(*)
    INTEGER(C_INT), VALUE         :: nPart
    REAL(C_DOUBLE), VALUE         :: dt
  END SUBROUTINE

  !-------------------------------------------------------------------------------------------------------------------------------
  ! LSERK4 per-stage push: one RK stage for PP_TimeDiscMethod 2 and 6.
  ! PartState and Pt_temp are uploaded and downloaded each call.
  ! Pt (acceleration), isActive, isPush, isNewPart are uploaded each call.
  !-------------------------------------------------------------------------------------------------------------------------------
  SUBROUTINE piclas_gpu_lserk_stage(PartState, Pt_temp, Pt,          &
                                     isActive, isPush, isNewPart,     &
                                     nPart, isStage1, RK_a, b_dt)    &
      BIND(C, NAME='piclas_gpu_lserk_stage')
    IMPORT :: C_DOUBLE, C_INT
    REAL(C_DOUBLE), INTENT(INOUT) :: PartState(*)  !< [6,nPart] pos+vel
    REAL(C_DOUBLE), INTENT(INOUT) :: Pt_temp(*)    !< [6,nPart] RK staging
    REAL(C_DOUBLE), INTENT(IN)    :: Pt(*)         !< [3,nPart] acceleration
    INTEGER(C_INT), INTENT(IN)    :: isActive(*)   !< active mask
    INTEGER(C_INT), INTENT(IN)    :: isPush(*)     !< charged-particle mask
    INTEGER(C_INT), INTENT(IN)    :: isNewPart(*)  !< new-particle mask
    INTEGER(C_INT), VALUE         :: nPart
    INTEGER(C_INT), VALUE         :: isStage1      !< 1 for stage 1, 0 otherwise
    REAL(C_DOUBLE), VALUE         :: RK_a          !< RK_a(iStage)
    REAL(C_DOUBLE), VALUE         :: b_dt          !< RK_b(iStage)*dt
  END SUBROUTINE

END INTERFACE

PUBLIC :: GPU_Init, GPU_Finalize, GPU_PushParticlesBatch, GPU_LSERKStageBatch

CONTAINS

!=================================================================================================================================
!> GPU_Init
!> Initialize CUDA device and allocate device buffers.
!> Called once during PICLas initialisation when PICLAS_USE_GPU=1.
!=================================================================================================================================
SUBROUTINE GPU_Init(nMaxPart)
  INTEGER, INTENT(IN) :: nMaxPart   !< PDM%maxParticleNumber
  INTEGER(C_INT) :: nMaxPart_c
  ! Load libpiclasGPU.dll now (after main() started, loader lock released).
  ! This avoids the Windows DLL loader deadlock that hung the process before main().
  CALL piclas_gpu_load_library()
  CALL piclas_gpu_init()
  nMaxPart_c = INT(nMaxPart, C_INT)
  CALL piclas_gpu_alloc_buffers(nMaxPart_c)
  CALL GPU_AllocActiveMask(nMaxPart)
  GPU_nMaxPart   = nMaxPart
  GPUInitialized = .TRUE.
END SUBROUTINE GPU_Init

!=================================================================================================================================
!> GPU_Finalize
!> Free device buffers and reset the CUDA device.
!> Called once during PICLas shutdown when PICLAS_USE_GPU=1.
!=================================================================================================================================
SUBROUTINE GPU_Finalize()
  CALL GPU_FreeActiveMask()
  CALL piclas_gpu_free_buffers()
  CALL piclas_gpu_finalize()
  GPUInitialized = .FALSE.
  GPU_nMaxPart   = 0
END SUBROUTINE GPU_Finalize

!=================================================================================================================================
!> GPU_PushParticlesBatch
!> Upload PartState to GPU, run the position-push kernel, download results.
!>
!> Handles the simple constant-dt case:
!>   PartState(1:3,iPart) += PartState(4:6,iPart) * dt
!> for all active particles (ParticleInside(iPart) = .TRUE.).
!>
!> Called from timedisc_TimeStep_DSMC when:
!>   - GPUInitialized = .TRUE.
!>   - UseVarTimeStep = .FALSE.
!>   - UseRotRefFrame = .FALSE.
!>   - DoSurfaceFlux  = .FALSE. (no fractional-dt push particles)
!=================================================================================================================================
SUBROUTINE GPU_PushParticlesBatch(PartState, ParticleInside, nPart, dt)
  REAL,    INTENT(INOUT) :: PartState(1:6, 1:*)   !< particle state array
  LOGICAL, INTENT(IN)    :: ParticleInside(1:*)   !< PDM%ParticleInside
  INTEGER, INTENT(IN)    :: nPart                 !< PDM%ParticleVecLength
  REAL,    INTENT(IN)    :: dt                    !< time step
  ! Local
  INTEGER(C_INT) :: nPart_c, newMax_c
  REAL(C_DOUBLE) :: dt_c
  INTEGER        :: newMax

  IF (nPart <= 0) RETURN

  ! Grow host + device buffers when particle count exceeds the capacity allocated
  ! during GPU_Init.  DSMC ionisation and surface emission can raise ParticleVecLength
  ! above PDM%maxParticleNumber (the value passed at init time).
  IF (nPart > GPU_nMaxPart) THEN
    newMax   = MAX(nPart, GPU_nMaxPart * 2)
    newMax_c = INT(newMax, C_INT)
    CALL piclas_gpu_free_buffers()
    CALL GPU_FreeActiveMask()
    CALL piclas_gpu_alloc_buffers(newMax_c)
    CALL GPU_AllocActiveMask(newMax)
    GPU_nMaxPart = newMax
  END IF

  ! Convert Fortran LOGICAL to C int (Fortran LOGICAL is not C bool)
  WHERE (ParticleInside(1:nPart))
    GPU_ActiveMask(1:nPart) = 1_C_INT
  ELSEWHERE
    GPU_ActiveMask(1:nPart) = 0_C_INT
  END WHERE

  nPart_c = INT(nPart, C_INT)
  dt_c    = REAL(dt,   C_DOUBLE)
  CALL piclas_gpu_push_particles(PartState, GPU_ActiveMask, nPart_c, dt_c)
END SUBROUTINE GPU_PushParticlesBatch

!=================================================================================================================================
!> GPU_LSERKStageBatch
!> Execute one LSERK4 RK stage on the GPU for PP_TimeDiscMethod 2 and 6.
!>
!> Converts Fortran LOGICAL masks to C int arrays, calls the CUDA entry point,
!> and clears PDM%IsNewPart for all active particles (mirroring the per-particle
!> CPU loop that sets IsNewPart=.FALSE. after the push).
!>
!> Called from timedisc_TimeStepByLSERK once per stage when UseGPUPush=.TRUE.
!=================================================================================================================================
SUBROUTINE GPU_LSERKStageBatch(PartState, Pt_temp, Pt,                        &
                                ParticleInside, IsNewPart, IsPush, nPart,     &
                                iStage, RK_a_stage, b_dt_stage)
  REAL,    INTENT(INOUT) :: PartState(1:6, 1:*)  !< particle state array
  REAL,    INTENT(INOUT) :: Pt_temp(1:6,   1:*)  !< LSERK staging array
  REAL,    INTENT(IN)    :: Pt(1:3,         1:*)  !< acceleration (force/mass)
  LOGICAL, INTENT(IN)    :: ParticleInside(1:*)   !< PDM%ParticleInside
  LOGICAL, INTENT(INOUT) :: IsNewPart(1:*)        !< PDM%IsNewPart
  LOGICAL, INTENT(IN)    :: IsPush(1:*)           !< isPushParticle mask (built by caller)
  INTEGER, INTENT(IN)    :: nPart                 !< PDM%ParticleVecLength
  INTEGER, INTENT(IN)    :: iStage                !< current RK stage (1..nRKStages)
  REAL,    INTENT(IN)    :: RK_a_stage            !< RK_a(iStage); 0 if iStage==1
  REAL,    INTENT(IN)    :: b_dt_stage            !< RK_b(iStage) * dt
  ! Local
  INTEGER :: iPart, newMax
  INTEGER(C_INT) :: nPart_c, isStage1_c, newMax_c
  REAL(C_DOUBLE) :: RK_a_c, b_dt_c

  IF (nPart <= 0) RETURN

  ! Grow host + device buffers when particle count exceeds the capacity allocated
  ! during GPU_Init.  Same guard as GPU_PushParticlesBatch.
  IF (nPart > GPU_nMaxPart) THEN
    newMax   = MAX(nPart, GPU_nMaxPart * 2)
    newMax_c = INT(newMax, C_INT)
    CALL piclas_gpu_free_buffers()
    CALL GPU_FreeActiveMask()
    CALL piclas_gpu_alloc_buffers(newMax_c)
    CALL GPU_AllocActiveMask(newMax)
    GPU_nMaxPart = newMax
  END IF

  ! Build integer masks from Fortran LOGICALs
  DO iPart = 1, nPart
    GPU_ActiveMask(iPart)    = MERGE(1_C_INT, 0_C_INT, ParticleInside(iPart))
    GPU_IsPushMask(iPart)    = MERGE(1_C_INT, 0_C_INT, &
                                     ParticleInside(iPart) .AND. IsPush(iPart))
    GPU_IsNewPartMask(iPart) = MERGE(1_C_INT, 0_C_INT, &
                                     ParticleInside(iPart) .AND. IsNewPart(iPart))
  END DO

  nPart_c    = INT(nPart,       C_INT)
  isStage1_c = INT(MERGE(1,0,iStage.EQ.1), C_INT)
  RK_a_c     = REAL(RK_a_stage, C_DOUBLE)
  b_dt_c     = REAL(b_dt_stage, C_DOUBLE)

  CALL piclas_gpu_lserk_stage(PartState, Pt_temp, Pt,                   &
                               GPU_ActiveMask, GPU_IsPushMask,           &
                               GPU_IsNewPartMask,                        &
                               nPart_c, isStage1_c, RK_a_c, b_dt_c)

  ! Mirror the CPU loop: set IsNewPart=.FALSE. for all active particles.
  ! The GPU kernel has already processed them (stage-1 treatment for newp=1).
  WHERE (ParticleInside(1:nPart)) IsNewPart(1:nPart) = .FALSE.

END SUBROUTINE GPU_LSERKStageBatch

END MODULE MOD_GPU_Interface
