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

PUBLIC :: GPU_AllocActiveMask, GPU_FreeActiveMask

CONTAINS

!=================================================================================================================================
!> Allocate (or re-allocate) the active-particle mask buffer.
!=================================================================================================================================
SUBROUTINE GPU_AllocActiveMask(nMaxPart)
  INTEGER, INTENT(IN) :: nMaxPart
  IF (ALLOCATED(GPU_ActiveMask)) DEALLOCATE(GPU_ActiveMask)
  ALLOCATE(GPU_ActiveMask(1:nMaxPart))
  GPU_ActiveMask = 0_C_INT
END SUBROUTINE GPU_AllocActiveMask

!=================================================================================================================================
!> Deallocate the active-particle mask buffer.
!=================================================================================================================================
SUBROUTINE GPU_FreeActiveMask()
  IF (ALLOCATED(GPU_ActiveMask)) DEALLOCATE(GPU_ActiveMask)
END SUBROUTINE GPU_FreeActiveMask

END MODULE MOD_GPU_Vars
