!=================================================================================================================================
! PICLas GPU acceleration — Fortran state variables
! Stores GPU initialisation state and a reusable integer-mask work buffer.
!=================================================================================================================================
MODULE MOD_GPU_Vars
USE ISO_C_BINDING, ONLY: C_INT, C_DOUBLE
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

!---------------------------------------------------------------------------------------------------------------------------------
! DSMC push masks (allocated alongside GPU_ActiveMask)
!   GPU_DtFracMask  — 1 if particle was inserted by a surface flux this step
!                     (PDM%dtFracPush=.TRUE.); kernel scales dt by GPU_DtFracRand
!   GPU_DtFracRand  — per-particle dt scaling: 1.0 for non-fresh particles,
!                     uniform [0,1] RNG draw for fresh ones (host-filled in
!                     iPart order so the RNG state matches the CPU loop)
!---------------------------------------------------------------------------------------------------------------------------------
INTEGER(C_INT),     ALLOCATABLE, PUBLIC :: GPU_DtFracMask(:)
REAL(C_DOUBLE),     ALLOCATABLE, PUBLIC :: GPU_DtFracRand(:)

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
  IF (ALLOCATED(GPU_DtFracMask))    DEALLOCATE(GPU_DtFracMask)
  IF (ALLOCATED(GPU_DtFracRand))    DEALLOCATE(GPU_DtFracRand)
  ALLOCATE(GPU_ActiveMask(1:nMaxPart))
  ALLOCATE(GPU_IsPushMask(1:nMaxPart))
  ALLOCATE(GPU_IsNewPartMask(1:nMaxPart))
  ALLOCATE(GPU_DtFracMask(1:nMaxPart))
  ALLOCATE(GPU_DtFracRand(1:nMaxPart))
  GPU_ActiveMask    = 0_C_INT
  GPU_IsPushMask    = 0_C_INT
  GPU_IsNewPartMask = 0_C_INT
  GPU_DtFracMask    = 0_C_INT
  GPU_DtFracRand    = 1.0_C_DOUBLE
END SUBROUTINE GPU_AllocActiveMask

!=================================================================================================================================
!> Deallocate the mask buffers.
!=================================================================================================================================
SUBROUTINE GPU_FreeActiveMask()
  IF (ALLOCATED(GPU_ActiveMask))    DEALLOCATE(GPU_ActiveMask)
  IF (ALLOCATED(GPU_IsPushMask))    DEALLOCATE(GPU_IsPushMask)
  IF (ALLOCATED(GPU_IsNewPartMask)) DEALLOCATE(GPU_IsNewPartMask)
  IF (ALLOCATED(GPU_DtFracMask))    DEALLOCATE(GPU_DtFracMask)
  IF (ALLOCATED(GPU_DtFracRand))    DEALLOCATE(GPU_DtFracRand)
END SUBROUTINE GPU_FreeActiveMask

END MODULE MOD_GPU_Vars
