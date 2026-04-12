!=================================================================================================================================
! PICLas GPU acceleration — Fortran state variables
! Stores GPU initialisation state and a reusable integer-mask work buffer.
!=================================================================================================================================
MODULE MOD_GPU_Vars
USE ISO_C_BINDING, ONLY: C_INT
IMPLICIT NONE
PRIVATE

!---------------------------------------------------------------------------------------------------------------------------------
! Public state
!---------------------------------------------------------------------------------------------------------------------------------
LOGICAL, PUBLIC :: GPUInitialized = .FALSE.  !< .TRUE. after GPU_Init has been called
INTEGER, PUBLIC :: GPU_nMaxPart   = 0        !< device buffer capacity (number of particles)

!---------------------------------------------------------------------------------------------------------------------------------
! Active-particle mask: INTEGER(C_INT) translation of PDM%ParticleInside.
! Re-used every time step to avoid repeated allocation.
!---------------------------------------------------------------------------------------------------------------------------------
INTEGER(C_INT), ALLOCATABLE, PUBLIC :: GPU_ActiveMask(:)

!---------------------------------------------------------------------------------------------------------------------------------
! LSERK push masks (allocated alongside GPU_ActiveMask)
!   GPU_IsPushMask   — 1 if particle is charged (velocity pushed), 0 if neutral
!   GPU_IsNewPartMask — 1 if particle is newly inserted (needs stage-1 treatment)
!---------------------------------------------------------------------------------------------------------------------------------
INTEGER(C_INT), ALLOCATABLE, PUBLIC :: GPU_IsPushMask(:)
INTEGER(C_INT), ALLOCATABLE, PUBLIC :: GPU_IsNewPartMask(:)

PUBLIC :: GPU_AllocActiveMask, GPU_FreeActiveMask

CONTAINS

!=================================================================================================================================
!> Allocate (or re-allocate) the active-particle mask buffer and LSERK masks.
!=================================================================================================================================
SUBROUTINE GPU_AllocActiveMask(nMaxPart)
  INTEGER, INTENT(IN) :: nMaxPart
  IF (ALLOCATED(GPU_ActiveMask))    DEALLOCATE(GPU_ActiveMask)
  IF (ALLOCATED(GPU_IsPushMask))    DEALLOCATE(GPU_IsPushMask)
  IF (ALLOCATED(GPU_IsNewPartMask)) DEALLOCATE(GPU_IsNewPartMask)
  ALLOCATE(GPU_ActiveMask(1:nMaxPart))
  ALLOCATE(GPU_IsPushMask(1:nMaxPart))
  ALLOCATE(GPU_IsNewPartMask(1:nMaxPart))
  GPU_ActiveMask    = 0_C_INT
  GPU_IsPushMask    = 0_C_INT
  GPU_IsNewPartMask = 0_C_INT
END SUBROUTINE GPU_AllocActiveMask

!=================================================================================================================================
!> Deallocate the mask buffers.
!=================================================================================================================================
SUBROUTINE GPU_FreeActiveMask()
  IF (ALLOCATED(GPU_ActiveMask))    DEALLOCATE(GPU_ActiveMask)
  IF (ALLOCATED(GPU_IsPushMask))    DEALLOCATE(GPU_IsPushMask)
  IF (ALLOCATED(GPU_IsNewPartMask)) DEALLOCATE(GPU_IsNewPartMask)
END SUBROUTINE GPU_FreeActiveMask

END MODULE MOD_GPU_Vars
