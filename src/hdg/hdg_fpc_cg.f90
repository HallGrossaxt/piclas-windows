!==================================================================================================================================
! Copyright (c) 2010-2019 Prof. Claus-Dieter Munz
! Copyright (c) 2016-2017 Gregor Gassner (github.com/project-fluxo/fluxo)
! Copyright (c) 2016-2017 Florian Hindenlang (github.com/project-fluxo/fluxo)
! Copyright (c) 2016-2017 Andrew Winters (github.com/project-fluxo/fluxo)
!
! This file is part of PICLas (gitlab.com/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the License.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

!==================================================================================================================================
!> Floating boundary condition (FPC) in the internal (non-PETSc) HDG CG solver via a capacitance matrix (Woodbury).
!>
!> The FPC adds, per electrically-connected conductor group k (1..FPC%nUniqueFPCBounds), one global scalar unknown phi_F,k.
!> With PETSc these are extra DOFs appended to the global matrix. Without PETSc we solve the bordered system
!>
!>     [ A   C ] [ lambda ]   [ b       ]
!>     [ C^T D ] [ phi_F  ] = [ Q/eps0  ]
!>
!> where A == A_nn is the normal-face HDG matrix (conductor faces masked; inverted by the existing CG_solver, see MatVec/
!> EvalResidual with FPCMaskConductor=.TRUE.), C is the conductor->normal coupling, D the conductor self-block and Q the
!> accumulated surface charge (FPC%Charge). Block elimination (capacitance matrix S = D - C^T A^-1 C) gives:
!>
!>   setup (once; whenever A changes -> FPCcapValid=.FALSE.):   z_l = A^-1 C_l ,  S = D - C^T Z ,  factor S
!>   per step:   solve A y = b_n  (masked CG) ;  phi_F = S^-1 (Q/eps0 - C^T y) ;  lambda_n = y - sum_l z_l phi_F,l
!>
!> Every conductor-face reduction collapses to a single ALLREDUCE of an m-vector over MPI_COMM_PICLAS because FPC (BC) faces
!> are unshared across ranks (no MPI_YOUR double-counting). See scope_fpc_cg_magnetron.md.
!>
!> STATUS 2026-07-14: VALIDATED against regressioncheck/WEK_poisson_PETSC/floating_boundary_condition_multi_FPC at
!> MPI=1/2/4 on the Windows/MS-MPI poisson build. FPC voltages match the PETSc reference to ~7-8 significant figures
!> (2.5471e10 / 4.9863e10 V), charges exact (5.0/10.0), identical across rank counts. See scope_fpc_cg_magnetron.md.
!==================================================================================================================================
MODULE MOD_HDG_FPC_CG
#if USE_HDG && !(USE_PETSC)
! MODULES
IMPLICIT NONE
PRIVATE

!> Ragged per-side scratch to back up lambda/RHS_face around the (side-effect-free) capacitance-matrix setup.
TYPE tRagged
  REAL,ALLOCATABLE :: v(:)
END TYPE tRagged
TYPE(tRagged),ALLOCATABLE :: bkpLambda(:),bkpRHS(:)

PUBLIC :: InitFPCviaCG
PUBLIC :: SolveFPCviaCG
PUBLIC :: FinalizeFPCviaCG
!==================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Build the capacitance matrix S and the cached columns z_l = A^-1 C_l. Call once after the HDG element matrices (Smat) are
!> available and again whenever A changes (load balance, dt). Assumes UseFPCviaCG=.TRUE. and FPC bookkeeping is initialised.
!==================================================================================================================================
SUBROUTINE InitFPCviaCG()
! MODULES
USE MOD_Globals
USE MOD_HDG_Vars   ,ONLY: FPC,HDG_Surf_N,FPCMaskConductor
USE MOD_HDG_Vars   ,ONLY: FPCcap,FPCcapInv,FPCcapValid
USE MOD_HDG_Tools  ,ONLY: CG_solver
USE MOD_Mesh_Vars  ,ONLY: nSides,N_SurfMesh
USE MOD_HDG_Vars   ,ONLY: nGP_face
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars ,ONLY: PerformLoadBalance   ! referenced by the LBWRITE macro
#endif /*USE_LOADBALANCE*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER :: l,SideID,m,NSide
REAL,ALLOCATABLE :: Dcol(:),Scol(:)   ! (1:m) working columns
!==================================================================================================================================
m = FPC%nUniqueFPCBounds
IF(m.LE.0) RETURN

! Allocate ragged per-side cache FPCz(1:m,nGP_face) and the m x m matrices
DO SideID=1,nSides
  NSide = N_SurfMesh(SideID)%NSide
  IF(ALLOCATED(HDG_Surf_N(SideID)%FPCz)) DEALLOCATE(HDG_Surf_N(SideID)%FPCz)
  ALLOCATE(HDG_Surf_N(SideID)%FPCz(1:m,1:nGP_face(NSide)))
  HDG_Surf_N(SideID)%FPCz = 0.
END DO ! SideID
SDEALLOCATE(FPCcap)   ; ALLOCATE(FPCcap(1:m,1:m))    ; FPCcap    = 0.
SDEALLOCATE(FPCcapInv); ALLOCATE(FPCcapInv(1:m,1:m)) ; FPCcapInv = 0.
ALLOCATE(Dcol(1:m),Scol(1:m))

! --- 1) For each group l: form C_l (unmasked M applied to indicator P_l, read on normal faces), the self/cross block D(:,l),
!        and solve A_nn z_l = C_l (masked CG). Backup/restore lambda & RHS_face so this is side-effect free.
CALL PushLambdaRHS()
DO l=1,m
  ! Indicator P_l: lambda = 1 on conductor faces of group l, 0 everywhere else
  CALL SetGroupIndicator(l)
  ! D(:,l) = restrict (unmasked M P_l) to each conductor group  -> Dcol(1:m)
  CALL ApplyUnmaskedRestrict(Dcol)
  FPCcap(:,l) = Dcol(:)              ! S starts as D; the -C^T Z term is subtracted below

  ! C_l lives on normal faces = (M P_l) there. MatVec result is in HDG_Surf_N%mv after ApplyUnmaskedRestrict.
  ! Use it as the RHS for the auxiliary solve A_nn z_l = C_l.
  CALL CopyMvToRHS_NormalOnly()     ! RHS_face(normal)=mv(normal); conductor & Dirichlet RHS set to 0
  CALL ZeroLambdaAll()              ! homogeneous initial guess -> pure A_nn^-1 (no Dirichlet lift)
  FPCMaskConductor = .TRUE.
  CALL CG_solver(1)                 ! lambda := A_nn^-1 C_l
  CALL StoreLambdaToFPCz(l)         ! FPCz(l,:) := lambda
END DO ! l

! --- 2) Subtract C^T Z:  S(k,l) = D(k,l) - C_k^T z_l, with C_k^T z_l = restrict(unmasked M z_l) to group k
!        (valid because z_l is 0 on conductor faces, so (M z_l)|conductor = A_cn z_l = C^T z_l).
DO l=1,m
  CALL LoadFPCzToLambda(l)          ! lambda := z_l (0 on conductor faces by construction)
  CALL ApplyUnmaskedRestrict(Scol)  ! Scol(k) = C_k^T z_l
  FPCcap(:,l) = FPCcap(:,l) - Scol(:)
END DO ! l
CALL PopLambdaRHS()

! --- 3) Invert the tiny m x m S
CALL InvertSmall(FPCcap,FPCcapInv,m)

DEALLOCATE(Dcol,Scol)
FPCcapValid = .TRUE.
LBWRITE(UNIT_stdOut,'(A,I0,A,I0,A)')' | FPC-via-CG: built ',m,' x ',m,' capacitance matrix (cached A^-1 C).'
END SUBROUTINE InitFPCviaCG


!==================================================================================================================================
!> Per-step FPC solve. On entry HDG_Surf_N%RHS_face holds b (the normal RHS incl. Dirichlet lift, as assembled by hdg_linear).
!> On exit lambda holds the FPC-consistent solution and FPC%Voltage holds phi_F. Replaces the bare CG_solver call.
!==================================================================================================================================
SUBROUTINE SolveFPCviaCG(iVar)
! MODULES
USE MOD_Globals
USE MOD_Globals_Vars ,ONLY: eps0
USE MOD_HDG_Vars     ,ONLY: FPC,HDG_Surf_N,nConductorBCsides,ConductorBC,FPCMaskConductor,FPCcapInv,FPCcapValid
USE MOD_HDG_Tools    ,ONLY: CG_solver
USE MOD_Mesh_Vars    ,ONLY: BC,BoundaryType
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
INTEGER,INTENT(IN) :: iVar
!----------------------------------------------------------------------------------------------------------------------------------
INTEGER :: m,l,BCsideID,SideID,BCState,iUnique
REAL,ALLOCATABLE :: Cty(:),g(:),phi(:)
!==================================================================================================================================
m = FPC%nUniqueFPCBounds
IF(.NOT.FPCcapValid) CALL InitFPCviaCG()
ALLOCATE(Cty(1:m),g(1:m),phi(1:m))

! 1) Normal solve y = A_nn^-1 b_n  (masked CG excludes the conductor faces; lambda_conductor stays 0)
FPCMaskConductor = .TRUE.
CALL CG_solver(iVar)                     ! lambda := y

! 2) C^T y = restrict(unmasked M y) to each conductor group (y is 0 on conductor faces after the masked solve)
CALL ApplyUnmaskedRestrict(Cty)

! 3) g_k = Q_k/eps0 ;  phi_F = S^-1 (g - C^T y)
g(:)   = FPC%Charge(1:m) / eps0
phi(:) = MATMUL(FPCcapInv, g - Cty)

! 4) lambda_n := y - sum_l z_l phi_l  ; set conductor faces to phi ; publish FPC%Voltage
CALL AxpyFPCz(phi)                       ! lambda := lambda - sum_l FPCz(l,:) phi(l)  (normal faces)
DO BCsideID=1,nConductorBCsides
  SideID  = ConductorBC(BCsideID)
  BCState = BoundaryType(BC(SideID),BC_STATE)
  iUnique = FPC%Group(BCState,2)
  HDG_Surf_N(SideID)%lambda(iVar,:) = phi(iUnique)
END DO
FPC%Voltage(1:m) = phi(1:m)

DEALLOCATE(Cty,g,phi)
END SUBROUTINE SolveFPCviaCG


!==================================================================================================================================
!> Apply the UNMASKED HDG operator to the vector currently in HDG_Surf_N%lambda and restrict the result to each conductor group:
!>   res(k) = sum over group-k conductor faces of (M lambda). Single ALLREDUCE over MPI_COMM_PICLAS (FPC faces unshared).
!==================================================================================================================================
SUBROUTINE ApplyUnmaskedRestrict(res)
! MODULES
USE MOD_Globals
USE MOD_HDG_Vars  ,ONLY: FPC,HDG_Surf_N,nConductorBCsides,ConductorBC,FPCMaskConductor
USE MOD_HDG_Tools ,ONLY: MatVec
USE MOD_Mesh_Vars ,ONLY: BC,BoundaryType
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
REAL,INTENT(OUT) :: res(1:FPC%nUniqueFPCBounds)
!----------------------------------------------------------------------------------------------------------------------------------
INTEGER :: BCsideID,SideID,BCState,iUnique
#if USE_MPI
REAL    :: resSend(1:FPC%nUniqueFPCBounds)
#endif /*USE_MPI*/
!==================================================================================================================================
FPCMaskConductor = .FALSE.               ! unmasked operator: conductor faces active
CALL MatVec(1,.FALSE.)                    ! mv := M lambda
FPCMaskConductor = .TRUE.

res = 0.
DO BCsideID=1,nConductorBCsides
  SideID  = ConductorBC(BCsideID)
  BCState = BoundaryType(BC(SideID),BC_STATE)
  iUnique = FPC%Group(BCState,2)
  res(iUnique) = res(iUnique) + SUM(HDG_Surf_N(SideID)%mv(1,:))
END DO
#if USE_MPI
! NB: use a separate send buffer, NOT MPI_IN_PLACE. MS-MPI zeros the buffer for in-place ALLREDUCE on this build
! (same issue avoided throughout piclas-win, e.g. VectorDotProductRR).
resSend = res
CALL MPI_ALLREDUCE(resSend,res,FPC%nUniqueFPCBounds,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_PICLAS,iError)
#endif /*USE_MPI*/
END SUBROUTINE ApplyUnmaskedRestrict


!==================================================================================================================================
!> Small dense inverse (m is 1..a few). Uses LAPACK DGETRF/DGETRI which PICLas already links.
!==================================================================================================================================
SUBROUTINE InvertSmall(Ain,Ainv,m)
USE MOD_Globals
IMPLICIT NONE
INTEGER,INTENT(IN) :: m
REAL,INTENT(IN)    :: Ain(m,m)
REAL,INTENT(OUT)   :: Ainv(m,m)
INTEGER :: ipiv(m),info
REAL    :: work(m*m)
!==================================================================================================================================
Ainv = Ain
CALL DGETRF(m,m,Ainv,m,ipiv,info)
IF(info.NE.0) CALL abort(__STAMP__,'FPC-via-CG: capacitance matrix LU failed (singular?), info=',IntInfoOpt=info)
CALL DGETRI(m,Ainv,m,ipiv,work,m*m,info)
IF(info.NE.0) CALL abort(__STAMP__,'FPC-via-CG: capacitance matrix inverse failed, info=',IntInfoOpt=info)
END SUBROUTINE InvertSmall


!==================================================================================================================================
!> Finalize
!==================================================================================================================================
SUBROUTINE FinalizeFPCviaCG()
USE MOD_HDG_Vars ,ONLY: FPCcap,FPCcapInv,FPCcapValid,HDG_Surf_N
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
INTEGER :: SideID
!==================================================================================================================================
SDEALLOCATE(FPCcap)
SDEALLOCATE(FPCcapInv)
IF(ALLOCATED(HDG_Surf_N))THEN
  DO SideID=1,nSides
    SDEALLOCATE(HDG_Surf_N(SideID)%FPCz)
  END DO
END IF
FPCcapValid = .FALSE.
END SUBROUTINE FinalizeFPCviaCG


! ---------------------------------------------------------------------------------------------------------------------------------
! Small ragged per-side scratch helpers (lambda/RHS_face/FPCz plumbing). iVar hard-wired to 1 (Poisson, PP_nVar==1).
! TODO(validate): generalise to iVar if a PP_nVar>1 HDG build ever uses FPC-via-CG.
! ---------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE SetGroupIndicator(l)
USE MOD_HDG_Vars ,ONLY: FPC,HDG_Surf_N,nConductorBCsides,ConductorBC
USE MOD_Mesh_Vars,ONLY: nSides,BC,BoundaryType
IMPLICIT NONE
INTEGER,INTENT(IN) :: l
INTEGER :: SideID,BCsideID,BCState,iUnique
!==================================================================================================================================
DO SideID=1,nSides
  HDG_Surf_N(SideID)%lambda(1,:) = 0.
END DO
DO BCsideID=1,nConductorBCsides
  SideID  = ConductorBC(BCsideID)
  BCState = BoundaryType(BC(SideID),BC_STATE)
  iUnique = FPC%Group(BCState,2)
  IF(iUnique.EQ.l) HDG_Surf_N(SideID)%lambda(1,:) = 1.
END DO
END SUBROUTINE SetGroupIndicator

SUBROUTINE CopyMvToRHS_NormalOnly()
USE MOD_HDG_Vars ,ONLY: HDG_Surf_N,nConductorBCsides,ConductorBC,nDirichletBCSides,DirichletBC
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
INTEGER :: SideID,BCsideID
!==================================================================================================================================
DO SideID=1,nSides
  HDG_Surf_N(SideID)%RHS_face(1,:) = HDG_Surf_N(SideID)%mv(1,:)
END DO
DO BCsideID=1,nConductorBCsides
  HDG_Surf_N(ConductorBC(BCsideID))%RHS_face(1,:) = 0.
END DO
DO BCsideID=1,nDirichletBCSides
  HDG_Surf_N(DirichletBC(BCsideID))%RHS_face(1,:) = 0.
END DO
END SUBROUTINE CopyMvToRHS_NormalOnly

SUBROUTINE ZeroLambdaAll()
USE MOD_HDG_Vars ,ONLY: HDG_Surf_N
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
INTEGER :: SideID
DO SideID=1,nSides
  HDG_Surf_N(SideID)%lambda(1,:) = 0.
END DO
END SUBROUTINE ZeroLambdaAll

SUBROUTINE StoreLambdaToFPCz(l)
USE MOD_HDG_Vars ,ONLY: HDG_Surf_N
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
INTEGER,INTENT(IN) :: l
INTEGER :: SideID
DO SideID=1,nSides
  HDG_Surf_N(SideID)%FPCz(l,:) = HDG_Surf_N(SideID)%lambda(1,:)
END DO
END SUBROUTINE StoreLambdaToFPCz

SUBROUTINE LoadFPCzToLambda(l)
USE MOD_HDG_Vars ,ONLY: HDG_Surf_N
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
INTEGER,INTENT(IN) :: l
INTEGER :: SideID
DO SideID=1,nSides
  HDG_Surf_N(SideID)%lambda(1,:) = HDG_Surf_N(SideID)%FPCz(l,:)
END DO
END SUBROUTINE LoadFPCzToLambda

SUBROUTINE AxpyFPCz(phi)
!> lambda := lambda - sum_l FPCz(l,:) * phi(l)   (applied on all sides; conductor faces are overwritten by caller)
USE MOD_HDG_Vars ,ONLY: FPC,HDG_Surf_N
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
REAL,INTENT(IN) :: phi(1:FPC%nUniqueFPCBounds)
INTEGER :: SideID,l
DO SideID=1,nSides
  DO l=1,FPC%nUniqueFPCBounds
    HDG_Surf_N(SideID)%lambda(1,:) = HDG_Surf_N(SideID)%lambda(1,:) - HDG_Surf_N(SideID)%FPCz(l,:)*phi(l)
  END DO
END DO
END SUBROUTINE AxpyFPCz

! lambda/RHS_face backup-restore around the setup (module-local ragged scratch)
SUBROUTINE PushLambdaRHS()
USE MOD_HDG_Vars ,ONLY: HDG_Surf_N,nGP_face
USE MOD_Mesh_Vars,ONLY: nSides,N_SurfMesh
IMPLICIT NONE
INTEGER :: SideID,NSide
IF(ALLOCATED(bkpLambda)) CALL FreeBkp()
ALLOCATE(bkpLambda(1:nSides),bkpRHS(1:nSides))
DO SideID=1,nSides
  NSide = N_SurfMesh(SideID)%NSide
  ALLOCATE(bkpLambda(SideID)%v(1:nGP_face(NSide)),bkpRHS(SideID)%v(1:nGP_face(NSide)))
  bkpLambda(SideID)%v = HDG_Surf_N(SideID)%lambda(1,:)
  bkpRHS(SideID)%v    = HDG_Surf_N(SideID)%RHS_face(1,:)
END DO
END SUBROUTINE PushLambdaRHS

SUBROUTINE PopLambdaRHS()
USE MOD_HDG_Vars ,ONLY: HDG_Surf_N
USE MOD_Mesh_Vars,ONLY: nSides
IMPLICIT NONE
INTEGER :: SideID
DO SideID=1,nSides
  HDG_Surf_N(SideID)%lambda(1,:)   = bkpLambda(SideID)%v
  HDG_Surf_N(SideID)%RHS_face(1,:) = bkpRHS(SideID)%v
END DO
CALL FreeBkp()
END SUBROUTINE PopLambdaRHS

SUBROUTINE FreeBkp()
IMPLICIT NONE
INTEGER :: SideID
IF(ALLOCATED(bkpLambda))THEN
  DO SideID=1,SIZE(bkpLambda)
    IF(ALLOCATED(bkpLambda(SideID)%v)) DEALLOCATE(bkpLambda(SideID)%v)
    IF(ALLOCATED(bkpRHS(SideID)%v))    DEALLOCATE(bkpRHS(SideID)%v)
  END DO
  DEALLOCATE(bkpLambda,bkpRHS)
END IF
END SUBROUTINE FreeBkp

#endif /*USE_HDG && !(USE_PETSC)*/
END MODULE MOD_HDG_FPC_CG
