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

END INTERFACE

PUBLIC :: GPU_Init, GPU_Finalize, GPU_PushParticlesBatch

CONTAINS

!=================================================================================================================================
!> GPU_Init
!> Initialize CUDA device and allocate device buffers.
!> Called once during PICLas initialisation when PICLAS_USE_GPU=1.
!=================================================================================================================================
SUBROUTINE GPU_Init(nMaxPart)
  INTEGER, INTENT(IN) :: nMaxPart   !< PDM%maxParticleNumber
  INTEGER(C_INT) :: nMaxPart_c
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
  INTEGER(C_INT) :: nPart_c
  REAL(C_DOUBLE) :: dt_c

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

END MODULE MOD_GPU_Interface
