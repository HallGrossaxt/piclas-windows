!==================================================================================================================================
! Copyright (c) 2010 - 2018 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
!
! This file is part of PICLas (piclas.boltzplatz.eu/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

MODULE MOD_Analyze_HDG
!===================================================================================================================================
! Contains DG analyze
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!===================================================================================================================================
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
!===================================================================================================================================
#if USE_HDG
PUBLIC :: InitCalcElectricTimeDerivativeSurface
PUBLIC :: InitCalcElectricPotentialExtrema
#endif /*USE_HDG*/
!===================================================================================================================================

CONTAINS

#if USE_HDG
!===================================================================================================================================
!> Create containers and communicators for each boundary on which the electric displacement current (EDC) is calculated and
!> agglomerated. This is done for all normal BCs except periodic BCs.
!>
!> 1.) Loop over all field BCs and check if the current processor is either the MPI root or has at least one of the BCs that
!>     contribute to the total electric displacement current (EDC). If yes, then this processor is part of the communicator
!> 2.) Create Mapping from electric displacement current (EDC) BC index to field BC index
!> 3.) Create Mapping from field BC index to electric displacement current (EDC) BC index
!> 4.) Check if field BC is on current proc (or MPI root)
!> 5.) Create MPI sub-communicators
!===================================================================================================================================
SUBROUTINE InitCalcElectricTimeDerivativeSurface()
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Mesh_Vars        ,ONLY: nBCs,BoundaryType
USE MOD_Analyze_Vars     ,ONLY: DoFieldAnalyze,CalcElectricTimeDerivative,EDC
!USE MOD_Equation_Vars    ,ONLY: Et
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars ,ONLY: PerformLoadBalance
#endif /*USE_LOADBALANCE*/
#if USE_MPI
USE MOD_Mesh_Vars        ,ONLY: BoundaryName,nBCSides,BC
#endif /*USE_MPI*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: iBC,iEDCBC
#if USE_MPI
LOGICAL,ALLOCATABLE :: BConProc(:)
INTEGER             :: SideID,color
#endif /*USE_MPI*/
!===================================================================================================================================
IF(.NOT.CalcElectricTimeDerivative) RETURN ! Read-in parameter that is set in  InitAnalyze() in analyze.f90

! 1.) Loop over all field BCs and check if the current processor is either the MPI root or has at least one of the BCs that
! contribute to the total electric displacement current. If yes, then this processor is part of the communicator
EDC%NBoundaries = 0
DO iBC=1,nBCs
  IF(BoundaryType(iBC,BC_ALPHA).NE.0) CYCLE
  EDC%NBoundaries = EDC%NBoundaries + 1
END DO

! If not electric displacement current boundaries exist, no measurement of the current can be performed
IF(EDC%NBoundaries.EQ.0) RETURN

! Automatically activate surface model analyze flag
DoFieldAnalyze = .TRUE.

! 2.) Create Mapping from electric displacement current BC index to field BC index
ALLOCATE(EDC%FieldBoundaries(EDC%NBoundaries))
EDC%NBoundaries = 0
DO iBC=1,nBCs
  IF(BoundaryType(iBC,BC_ALPHA).NE.0) CYCLE
  EDC%NBoundaries = EDC%NBoundaries + 1
  EDC%FieldBoundaries(EDC%NBoundaries) = iBC
END DO

! Allocate the container
ALLOCATE(EDC%Current(1:EDC%NBoundaries))
EDC%Current = 0.

! 3.) Create Mapping from field BC index to electric displacement current BC index
ALLOCATE(EDC%BCIDToEDCBCID(nBCs))
EDC%BCIDToEDCBCID = -1
DO iEDCBC = 1, EDC%NBoundaries
  iBC = EDC%FieldBoundaries(iEDCBC)
  EDC%BCIDToEDCBCID(iBC) = iEDCBC
END DO ! iEDCBC = 1, EDC%NBoundaries

#if USE_MPI
! 4.) Check if field BC is on current proc (or MPI root)
ALLOCATE(BConProc(EDC%NBoundaries))
BConProc = .FALSE.
IF(MPIRoot)THEN
  BConProc = .TRUE.
ELSE
  DO SideID=1,nBCSides
    IF(BoundaryType(BC(SideID),BC_ALPHA).NE.0) CYCLE
    iBC     = BC(SideID)
    iEDCBC  = EDC%BCIDToEDCBCID(iBC)
    BConProc(iEDCBC) = .TRUE.
  END DO ! SideID=1,nBCSides
END IF ! MPIRoot

! 5.) Create MPI sub-communicators
ALLOCATE(EDC%COMM(EDC%NBoundaries))
DO iEDCBC = 1, EDC%NBoundaries
  ! create new communicator
  color = MERGE(iEDCBC, MPI_UNDEFINED, BConProc(iEDCBC))

  ! set communicator id
  EDC%COMM(iEDCBC)%ID=iEDCBC

  ! create new emission communicator for electric displacement current communication. Pass MPI_INFO_NULL as rank to follow the original ordering
  CALL MPI_COMM_SPLIT(MPI_COMM_PICLAS, color, 0, EDC%COMM(iEDCBC)%UNICATOR, iError)

  ! Find my rank on the shared communicator, comm size and proc name
  IF(BConProc(iEDCBC))THEN
    CALL MPI_COMM_RANK(EDC%COMM(iEDCBC)%UNICATOR, EDC%COMM(iEDCBC)%MyRank, iError)
    CALL MPI_COMM_SIZE(EDC%COMM(iEDCBC)%UNICATOR, EDC%COMM(iEDCBC)%nProcs, iError)

    ! inform about size of emission communicator
    IF (EDC%COMM(iEDCBC)%MyRank.EQ.0) THEN
#if USE_LOADBALANCE
      IF(.NOT.PerformLoadBalance)&
#endif /*USE_LOADBALANCE*/
          WRITE(UNIT_StdOut,'(A,I0,A,I0,A)') ' Electric displacement current: Emission-Communicator ',iEDCBC,' on ',&
              EDC%COMM(iEDCBC)%nProcs,' procs for '//TRIM(BoundaryName(EDC%FieldBoundaries(iEDCBC)))
    END IF
  END IF ! BConProc(iEDCBC)
END DO ! iEDCBC = 1, EDC%NBoundaries
DEALLOCATE(BConProc)
#endif /*USE_MPI*/
END SUBROUTINE InitCalcElectricTimeDerivativeSurface


!===================================================================================================================================
!> Create containers and communicators for each boundary on which the electric potential extema (EPE) are calculated (min/max
!> values). This is done for all normal BCs except periodic, Neumann and FPC BCs.
!> Skips the BC_TYPE 1 (periodic) + 10,11,12 (Neumann) + FPC (20)
!>
!> 1.) Loop over all field BCs and check if the current processor is either the MPI root or has at least one of the BCs that
!>     contribute to the electric potential extrema (EPE). If yes, then this processor is part of the communicator
!> 2.) Create Mapping from electric potential extrema (EPE) BC index to field BC index
!> 3.) Create Mapping from field BC index to electric potential extrema (EPE) BC index
!> 4.) Check if field BC is on current proc (or MPI root)
!> 5.) Create MPI sub-communicators
!===================================================================================================================================
SUBROUTINE InitCalcElectricPotentialExtrema()
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Mesh_Vars        ,ONLY: nBCs,BoundaryType
USE MOD_Analyze_Vars     ,ONLY: DoFieldAnalyze,CalcElectricPotentialExtrema,EPE
!USE MOD_Equation_Vars    ,ONLY: Et
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars ,ONLY: PerformLoadBalance
#endif /*USE_LOADBALANCE*/
#if USE_MPI
USE MOD_Mesh_Vars        ,ONLY: BoundaryName,nBCSides,BC
#endif /*USE_MPI*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: iBC,iEPEBC
#if USE_MPI
LOGICAL,ALLOCATABLE :: BConProc(:)
INTEGER             :: SideID,color
#endif /*USE_MPI*/
!===================================================================================================================================
IF(.NOT.CalcElectricPotentialExtrema) RETURN ! Read-in parameter that is set in  InitAnalyze() in analyze.f90

! 1.) Loop over all field BCs and check if the current processor is either the MPI root or has at least one of the BCs that
! contribute to the electric potential extrema (EPE). If yes, then this processor is part of the communicator
EPE%NBoundaries = 0
DO iBC=1,nBCs
  IF(BoundaryType(iBC,BC_ALPHA).NE.0) CYCLE ! Skip periodic BC
  IF(ANY(BoundaryType(iBC,BC_TYPE).EQ.(/10,11,12/))) CYCLE ! Skip Neumann BC
  IF(BoundaryType(iBC,BC_TYPE).EQ.20) CYCLE ! Skip FPC BC
  EPE%NBoundaries = EPE%NBoundaries + 1
END DO

! If no electric potential extrema (EPE) boundaries exist, no measurement of the current can be performed
IF(EPE%NBoundaries.EQ.0) RETURN

! Automatically activate surface model analyze flag
DoFieldAnalyze = .TRUE.

! 2.) Create Mapping from electric potential extrema (EPE) BC index to field BC index
ALLOCATE(EPE%FieldBoundaries(EPE%NBoundaries))
EPE%NBoundaries = 0
DO iBC=1,nBCs
  IF(BoundaryType(iBC,BC_ALPHA).NE.0) CYCLE ! Skip periodic BC
  IF(ANY(BoundaryType(iBC,BC_TYPE).EQ.(/10,11,12/))) CYCLE ! Skip Neumann BC
  IF(BoundaryType(iBC,BC_TYPE).EQ.20) CYCLE ! Skip FPC BC
  EPE%NBoundaries = EPE%NBoundaries + 1
  EPE%FieldBoundaries(EPE%NBoundaries) = iBC
END DO

! Allocate the container
ALLOCATE(EPE%Minimum(1:EPE%NBoundaries))
EPE%Minimum = 0.
ALLOCATE(EPE%Maximum(1:EPE%NBoundaries))
EPE%Maximum = 0.

! 3.) Create Mapping from field BC index to electric potential extrema (EPE) BC index
ALLOCATE(EPE%BCIDToEPEBCID(nBCs))
EPE%BCIDToEPEBCID = -1
DO iEPEBC = 1, EPE%NBoundaries
  iBC = EPE%FieldBoundaries(iEPEBC)
  EPE%BCIDToEPEBCID(iBC) = iEPEBC
END DO ! iEPEBC = 1, EPE%NBoundaries

#if USE_MPI
! 4.) Check if field BC is on current proc (or MPI root)
ALLOCATE(BConProc(EPE%NBoundaries))
BConProc = .FALSE.
IF(MPIRoot)THEN
  BConProc = .TRUE.
ELSE
  DO SideID=1,nBCSides
    iBC    = BC(SideID)
    IF(BoundaryType(iBC,BC_ALPHA).NE.0) CYCLE ! Skip periodic BC
    IF(ANY(BoundaryType(iBC,BC_TYPE).EQ.(/10,11,12/))) CYCLE ! Skip Neumann BC
    IF(BoundaryType(iBC,BC_TYPE).EQ.20) CYCLE ! Skip FPC BC
    iEPEBC = EPE%BCIDToEPEBCID(iBC)
    BConProc(iEPEBC) = .TRUE.
  END DO ! SideID=1,nBCSides
END IF ! MPIRoot

! 5.) Create MPI sub-communicators
ALLOCATE(EPE%COMM(EPE%NBoundaries))
DO iEPEBC = 1, EPE%NBoundaries
  ! create new communicator
  color = MERGE(iEPEBC, MPI_UNDEFINED, BConProc(iEPEBC))

  ! set communicator id
  EPE%COMM(iEPEBC)%ID=iEPEBC

  ! create new emission communicator for electric potential extrema (EPE) communication. Pass MPI_INFO_NULL as rank to follow the original ordering
  CALL MPI_COMM_SPLIT(MPI_COMM_PICLAS, color, 0, EPE%COMM(iEPEBC)%UNICATOR, iError)

  ! Find my rank on the shared communicator, comm size and proc name
  IF(BConProc(iEPEBC))THEN
    CALL MPI_COMM_RANK(EPE%COMM(iEPEBC)%UNICATOR, EPE%COMM(iEPEBC)%MyRank, iError)
    CALL MPI_COMM_SIZE(EPE%COMM(iEPEBC)%UNICATOR, EPE%COMM(iEPEBC)%nProcs, iError)

    ! inform about size of emission communicator
    IF (EPE%COMM(iEPEBC)%MyRank.EQ.0) THEN
#if USE_LOADBALANCE
      IF(.NOT.PerformLoadBalance)&
#endif /*USE_LOADBALANCE*/
          WRITE(UNIT_StdOut,'(A,I0,A,I0,A)') ' Electric potential extrema (EPE): Emission-Communicator ',iEPEBC,' on ',&
              EPE%COMM(iEPEBC)%nProcs,' procs for '//TRIM(BoundaryName(EPE%FieldBoundaries(iEPEBC)))
    END IF
  END IF ! BConProc(iEPEBC)
END DO ! iEPEBC = 1, EPE%NBoundaries
DEALLOCATE(BConProc)
#endif /*USE_MPI*/
END SUBROUTINE InitCalcElectricPotentialExtrema
#endif /*USE_HDG*/

END MODULE MOD_Analyze_HDG
