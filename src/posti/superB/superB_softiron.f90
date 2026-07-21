!==================================================================================================================================
! Copyright (c) 2019 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
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

!==================================================================================================================================
!> superB soft-magnetic-material correction via the Reduced Scalar Potential (RSP).
!>
!> After superB has computed the free-space field into N_BG%BGField (= mu0*(H_s + M), Steps 1-4 of superB_main), regions of soft
!> magnetic steel (mu_r>1) magnetise and back-react. RSP splits H = H_s - grad(Psi) and enforces div(B)=0:
!>
!>     div( mu_r grad Psi ) = div( mu_r H_s + M )                                          (RSP-PDE)
!>     H = H_s - grad Psi ,   B = mu0 ( mu_r H + M )                                        (reconstruction)
!>
!> The source is NOT evaluated in that form. superB's free-space field obeys div(H_s + M) = div(B_free)/mu0 = 0 identically, so
!>
!>     div( mu_r H_s + M ) == div( (mu_r - 1) H_s )                                        (source actually used)
!>
!> and the second form is the only usable one. H_s comes from superB by differentiating PsiMag, which is itself a sum over discrete
!> surface point charges; taking a second derivative of that amplifies the quadrature noise. In the first form the two large terms
!> div(mu_r H_s) and div(M) have to cancel that noise against each other wherever mu_r=1, and they do not: a magnet inside the mesh
!> gave a mu_r=1 error of rel~1 that did NOT converge under N-refinement (N=2,3,4,5). The second form is identically zero wherever
!> mu_r=1 -- no cancellation, no dependence on M at all, and the source is supported only inside the soft-magnetic material. It makes
!> the mu_r=1 regression exact by construction rather than merely convergent.
!>
!> This is a variable-coefficient scalar Poisson identical to the HDG dielectric operator (chitens = mu_r, set by SetChiTensFromMuR
!> before InitHDG), so the LHS needs no new code. The RHS is the interesting part.
!>
!> HDG derivation of the div(G) source. The physically conserved flux is F = mu_r grad Psi - G (= -B/mu0), so the HDG local and
!> trace equations pick up G in two distinct places:
!>
!>   element-local (u) equation:  ... = -( div G , v )_K                 -- STRONG volume source, no face term
!>   trace (lambda) equation   :  ... = sum_K < G.n_out , mu >_dK        -- Neumann-style flux, accumulated per face
!>
!> (Formally: (G,grad v)_K - <G.n,v>_dK = -(div G, v)_K -- the face part of the weak form belongs to the TRACE equation, not to
!> the element equation.) The trace term is what carries the interface jump [[G.n]] at steel/air and magnet surfaces, i.e. the
!> entire soft-iron physics. An earlier version used only the weak volume term int(G.grad v) and no trace term; it failed the
!> mu_r=1 regression (rel=0.33) because the dropped flux left a spurious correction.
!>
!> Sign convention is anchored on piclas' own HDG conventions: CalcSourceHDG returns resu = div(chitens grad u) (cf. IniExactFunc
!> 105) and RHS_vol = -JwGP*resu, so here resu = div(G); the Neumann CASE(11) in hdg_linear.f90 adds +(q.n)*SurfElem*wGP*wGP with
!> q = chitens grad u to RHS_face, so here the trace term enters with q.n = G.n_out.
!>
!> For mu_r=1 this must be a no-op: G = H_s + M = B_free/mu0 is divergence free AND has continuous normal component, so both the
!> volume source and the face jumps vanish and Psi = 0. That is the regression gate.
!>
!> Handed to the existing HDG linear solver via MOD_HDG_Vars::SoftIronRHSVol / SoftIronQnFace / UseSoftIronRSP (two small guarded
!> hooks in HDGLinear), reusing the validated PETSc-free CG. Guarded by USE_SUPER_B && USE_HDG, active only with UseMagneticMaterials.
!==================================================================================================================================
MODULE MOD_SuperB_SoftIron
#if USE_SUPER_B && USE_HDG
IMPLICIT NONE
PRIVATE
PUBLIC :: SolveSoftIronRSP, SolveSoftIronRSPDeferred
!==================================================================================================================================
CONTAINS

!==================================================================================================================================
!> Assemble the RSP weak source, solve div(mu_r grad Psi)=div(mu_r H_s + M) with the HDG CG, and overwrite N_BG%BGField with the
!> corrected B = mu0(mu_r H + M). No-op unless UseMagneticMaterials.
!==================================================================================================================================
SUBROUTINE SolveSoftIronRSP()
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Globals_Vars       ,ONLY: mu0
USE MOD_SuperB_Vars        ,ONLY: UseMagneticMaterials, MagneticMaterial
USE MOD_SuperB_Vars        ,ONLY: NumOfPermanentMagnets, PermanentMagnets, PermanentMagnetInfo
USE MOD_Interpolation_Vars ,ONLY: N_BG, N_Inter, NMax
USE MOD_Mesh_Vars          ,ONLY: N_VolMesh, N_SurfMesh, offSetElem, nElems, nSides, ElemToSide
USE MOD_DG_Vars            ,ONLY: N_DG_Mapping, U_N
USE MOD_HDG_Vars           ,ONLY: UseSoftIronRSP, SoftIronRHSVol, SoftIronQnFace, nGP_face
USE MOD_HDG_Linear         ,ONLY: HDGLinear
USE MOD_ProlongToFace      ,ONLY: ProlongToFace_Side
#ifdef PARTICLES
USE MOD_PICDepo_Vars       ,ONLY: DoDeposition
#endif /*PARTICLES*/
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER :: iElem, Nloc, NSide, i, j, k, p, q, s, a, r, iMagnet, iLocSide, SideID, flip
#ifdef PARTICLES
LOGICAL :: DoDepositionBak
#endif /*PARTICLES*/
REAL    :: mur, Mvec(3), Hsvec(3), Gvec(3), wpqs, acc, nsgn
REAL    :: maxDiff, maxB, Bold(3), Bnew(3)
REAL    :: matVol, matH(3), matHs(3), matB(3)   ! volume-weighted averages over the tagged material region
#if USE_MPI
REAL    :: sbuf, sbuf3(3)
#endif /*USE_MPI*/
! Per-element scratch (allocated to the element's Nloc)
REAL,ALLOCATABLE :: Gt1(:,:,:), Gt2(:,:,:), Gt3(:,:,:)   ! contravariant fluxes (J a^i . G) at each GP
REAL,ALLOCATABLE :: Dmat(:,:)                            ! strong 1D derivative matrix, Dmat(i,a) = l_a'(xi_i)
REAL,ALLOCATABLE :: Gvol(:,:,:,:), Gface(:,:,:)          ! G in the volume / prolonged to one face
REAL,ALLOCATABLE :: Javol(:,:,:,:), Jaface(:,:,:)        ! the side's contravariant metric vector J*a^i, likewise prolonged
! Cache H_s (=BGField/mu0 - M) per element so B can be rebuilt after the solve overwrites nothing but BGField
TYPE tHsElem
  REAL,ALLOCATABLE :: Hs(:,:,:,:)                          ! (1:3,0:Nloc,0:Nloc,0:Nloc)
  REAL,ALLOCATABLE :: G (:,:,:,:)                          ! (1:3,0:Nloc,0:Nloc,0:Nloc)
END TYPE tHsElem
TYPE(tHsElem),ALLOCATABLE :: HsStore(:)
!==================================================================================================================================
IF(.NOT.UseMagneticMaterials) RETURN
SWRITE(UNIT_stdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' SOFT-IRON RSP CORRECTION (div(mu_r grad Psi) = div(mu_r H_s + M)) ...'

! HDGLinear writes into U_N (DG solution + gradient E); superB's lean init skips InitDG, so allocate the two components it needs.
IF(.NOT.ALLOCATED(U_N))THEN
  ALLOCATE(U_N(1:nElems))
  DO iElem=1,nElems
    Nloc = N_DG_Mapping(2,iElem+offSetElem)
    ALLOCATE(U_N(iElem)%U(PP_nVar,0:Nloc,0:Nloc,0:Nloc)); U_N(iElem)%U = 0.
    ALLOCATE(U_N(iElem)%E(1:3    ,0:Nloc,0:Nloc,0:Nloc)); U_N(iElem)%E = 0.
  END DO
END IF

ALLOCATE(SoftIronRHSVol(1:nElems))
ALLOCATE(HsStore(1:nElems))
ALLOCATE(SoftIronQnFace(1:nGP_face(NMax),1:nSides))
SoftIronQnFace = 0.

! ---------------------------------------------------------------------------------------------------------------------------------
! 1) Per element: H_s = BGField/mu0 - M ; G = mu_r H_s + M ; contravariant flux Gti = Metrics_iTilde . G ; and the STRONG volume
!    source. With RHS_vol = -JwGP*div(G) and JwGP = J*w(p)w(q)w(s), div(G) = (1/J)(d_xi Gt1 + d_eta Gt2 + d_zeta Gt3), the Jacobian
!    cancels:
!      RHSvol(r) = - w(p)w(q)w(s) * [ sum_a D(p,a) Gt1(a,q,s) + sum_a D(q,a) Gt2(p,a,s) + sum_a D(s,a) Gt3(p,q,a) ]
!    D is the strong derivative matrix, recovered from the stored weak one: Domega(i,j) = w(i)/w(j)*D(i,j).
! ---------------------------------------------------------------------------------------------------------------------------------
DO iElem=1,nElems
  Nloc = N_DG_Mapping(2,iElem+offSetElem)
  ALLOCATE(HsStore(iElem)%Hs(1:3,0:Nloc,0:Nloc,0:Nloc))
  ALLOCATE(HsStore(iElem)%G (1:3,0:Nloc,0:Nloc,0:Nloc))
  ALLOCATE(SoftIronRHSVol(iElem)%RHSvol(1:(Nloc+1)**3))
  ALLOCATE(Gt1(0:Nloc,0:Nloc,0:Nloc), Gt2(0:Nloc,0:Nloc,0:Nloc), Gt3(0:Nloc,0:Nloc,0:Nloc))
  ALLOCATE(Dmat(0:Nloc,0:Nloc))
  DO a=0,Nloc; DO i=0,Nloc
    Dmat(i,a) = N_Inter(Nloc)%Domega(i,a)*N_Inter(Nloc)%wGP(a)/N_Inter(Nloc)%wGP(i)
  END DO; END DO

  ! H_s, G, contravariant fluxes at every GP
  DO k=0,Nloc; DO j=0,Nloc; DO i=0,Nloc
    IF(NumOfPermanentMagnets.GT.0)THEN
      iMagnet = PermanentMagnets(iElem)%Flag(i,j,k)
    ELSE
      iMagnet = 0
    END IF
    IF(iMagnet.GT.0)THEN; Mvec = PermanentMagnetInfo(iMagnet)%Magnetisation(:); ELSE; Mvec = 0.; END IF
    mur   = MagneticMaterial(iElem)%MuRField(i,j,k)
    Hsvec = N_BG(iElem)%BGField(1:3,i,j,k)/mu0 - Mvec          ! H_s
    HsStore(iElem)%Hs(1:3,i,j,k) = Hsvec
    Gvec  = (mur-1.0)*Hsvec                                    ! G = (mu_r - 1) H_s , see header
    HsStore(iElem)%G(1:3,i,j,k)  = Gvec
    Gt1(i,j,k) = DOT_PRODUCT(N_VolMesh(iElem)%Metrics_fTilde(1:3,i,j,k),Gvec)
    Gt2(i,j,k) = DOT_PRODUCT(N_VolMesh(iElem)%Metrics_gTilde(1:3,i,j,k),Gvec)
    Gt3(i,j,k) = DOT_PRODUCT(N_VolMesh(iElem)%Metrics_hTilde(1:3,i,j,k),Gvec)
  END DO; END DO; END DO

  ! Strong divergence of the contravariant flux -> per-DOF source
  DO s=0,Nloc; DO q=0,Nloc; DO p=0,Nloc
    wpqs = N_Inter(Nloc)%wGP(p)*N_Inter(Nloc)%wGP(q)*N_Inter(Nloc)%wGP(s)
    acc  = 0.
    DO a=0,Nloc
      acc = acc + Dmat(p,a)*Gt1(a,q,s) &
                + Dmat(q,a)*Gt2(p,a,s) &
                + Dmat(s,a)*Gt3(p,q,a)
    END DO
    r = s*(Nloc+1)**2 + q*(Nloc+1) + p + 1
    SoftIronRHSVol(iElem)%RHSvol(r) = -wpqs*acc
  END DO; END DO; END DO

  DEALLOCATE(Gt1,Gt2,Gt3,Dmat)
END DO ! iElem

! ---------------------------------------------------------------------------------------------------------------------------------
! 1b) Trace-equation flux: for every local element face, prolong G to the face GPs and accumulate (G.n_out)*SurfElem*wGP*wGP into
!     the side. Both adjacent elements contribute with their own outward normal, so an inner side ends up holding the jump
!     [[G.n]] (zero wherever G.n is continuous, e.g. everywhere for mu_r=1). MPI and mortar sides are reduced later by
!     Mask_MPIsides / SmallToBigMortar_HDG in HDGLinear, exactly like the regular RHS_face.
! ---------------------------------------------------------------------------------------------------------------------------------
! The outward n*SurfElem of a local side is just +/- the element's own contravariant metric vector (J*a^i) prolonged to that face,
! which is what elem_mat.f90:111-125 uses to build SurfElemLoc. Taking it from the element rather than from
! N_SurfMesh%NormVec/SurfElem keeps this loop purely element-local, so it does not depend on the master/slave orientation
! convention of the side -- which is exactly what made an earlier NormVec-based version disagree between MPI=1, 2 and 4.
DO iElem=1,nElems
  Nloc = N_DG_Mapping(2,iElem+offSetElem)
  ALLOCATE(Gvol(1:3,0:Nloc,0:Nloc,0:Nloc), Gface(1:3,0:Nloc,0:Nloc))
  ALLOCATE(Javol(1:3,0:Nloc,0:Nloc,0:Nloc), Jaface(1:3,0:Nloc,0:Nloc))
  DO iLocSide=1,6
    SideID = ElemToSide(E2S_SIDE_ID,iLocSide,iElem)
    flip   = ElemToSide(E2S_FLIP   ,iLocSide,iElem)
    NSide  = N_SurfMesh(SideID)%NSide
    IF(NSide.NE.Nloc) CALL abort(__STAMP__,'SolveSoftIronRSP: p-adaption (NSide/=Nloc) is not supported by the RSP source')
    SELECT CASE(iLocSide)
    CASE(XI_MINUS)  ; Javol = N_VolMesh(iElem)%Metrics_fTilde ; nsgn = -1.
    CASE(XI_PLUS)   ; Javol = N_VolMesh(iElem)%Metrics_fTilde ; nsgn =  1.
    CASE(ETA_MINUS) ; Javol = N_VolMesh(iElem)%Metrics_gTilde ; nsgn = -1.
    CASE(ETA_PLUS)  ; Javol = N_VolMesh(iElem)%Metrics_gTilde ; nsgn =  1.
    CASE(ZETA_MINUS); Javol = N_VolMesh(iElem)%Metrics_hTilde ; nsgn = -1.
    CASE(ZETA_PLUS) ; Javol = N_VolMesh(iElem)%Metrics_hTilde ; nsgn =  1.
    END SELECT
    ! Prolong both with the element's own flip -> side-local (p,q) ordering, matching the side's RHS_face DOF ordering.
    ! (wGP(p)*wGP(q) is invariant under the flip permutations, so no index back-mapping is needed for the weights.)
    Gvol = HsStore(iElem)%G
    CALL ProlongToFace_Side(3,Nloc,iLocSide,flip,Gvol ,Gface )
    CALL ProlongToFace_Side(3,Nloc,iLocSide,flip,Javol,Jaface)
    DO q=0,NSide; DO p=0,NSide
      r = q*(NSide+1) + p + 1
      SoftIronQnFace(r,SideID) = SoftIronQnFace(r,SideID) &
                               + nsgn*DOT_PRODUCT(Gface(1:3,p,q),Jaface(1:3,p,q))*N_Inter(NSide)%wGP(p)*N_Inter(NSide)%wGP(q)
    END DO; END DO
  END DO ! iLocSide
  DEALLOCATE(Gvol,Gface,Javol,Jaface)
END DO ! iElem

! ---------------------------------------------------------------------------------------------------------------------------------
! 2) Solve with the existing HDG linear solver (chitens already = mu_r; BCs from the mesh -> Psi Dirichlet). Neutralise the particle
!    charge source (IniExactFunc=0 + DoDeposition=.FALSE. -> CalcSourceHDG returns 0); our weak source is added via the hook.
! ---------------------------------------------------------------------------------------------------------------------------------
#ifdef PARTICLES
DoDepositionBak = DoDeposition
DoDeposition    = .FALSE.
#endif /*PARTICLES*/
UseSoftIronRSP = .TRUE.
CALL HDGLinear(0.)
UseSoftIronRSP = .FALSE.
#ifdef PARTICLES
DoDeposition = DoDepositionBak
#endif /*PARTICLES*/

! ---------------------------------------------------------------------------------------------------------------------------------
! 3) Reconstruct H = H_s - grad Psi = H_s + U_N%E (PostProcessGradientHDG stored E = -grad Psi) and B = mu0(mu_r H + M);
!    overwrite N_BG%BGField.
! ---------------------------------------------------------------------------------------------------------------------------------
maxDiff = 0.; maxB = 0.
matVol = 0.; matH = 0.; matHs = 0.; matB = 0.
DO iElem=1,nElems
  Nloc = N_DG_Mapping(2,iElem+offSetElem)
  DO k=0,Nloc; DO j=0,Nloc; DO i=0,Nloc
    IF(NumOfPermanentMagnets.GT.0)THEN
      iMagnet = PermanentMagnets(iElem)%Flag(i,j,k)
    ELSE
      iMagnet = 0
    END IF
    IF(iMagnet.GT.0)THEN; Mvec = PermanentMagnetInfo(iMagnet)%Magnetisation(:); ELSE; Mvec = 0.; END IF
    mur   = MagneticMaterial(iElem)%MuRField(i,j,k)
    Bold  = N_BG(iElem)%BGField(1:3,i,j,k)                           ! free-space B = mu0(H_s + M)
    Hsvec = HsStore(iElem)%Hs(1:3,i,j,k) + U_N(iElem)%E(1:3,i,j,k)   ! H = H_s - grad Psi
    Bnew  = mu0*(mur*Hsvec + Mvec)                                   ! B = mu0(mu_r H + M)
    N_BG(iElem)%BGField(1:3,i,j,k) = Bnew
    maxDiff = MAX(maxDiff, SQRT(SUM((Bnew-Bold)**2)))
    maxB    = MAX(maxB,    SQRT(SUM(Bold**2)))
    ! Volume-weighted averages over the tagged material region (analytic validation, e.g. sphere: <H>/H_0 = 3/(mu_r+2))
    IF(MagneticMaterial(iElem)%MatTag(i,j,k).GT.0)THEN
      wpqs   = N_Inter(Nloc)%wGP(i)*N_Inter(Nloc)%wGP(j)*N_Inter(Nloc)%wGP(k)/N_VolMesh(iElem)%sJ(i,j,k)
      matVol = matVol + wpqs
      matH   = matH   + wpqs*Hsvec
      matHs  = matHs  + wpqs*HsStore(iElem)%Hs(1:3,i,j,k)
      matB   = matB   + wpqs*Bnew
    END IF
  END DO; END DO; END DO
END DO ! iElem
#if USE_MPI
! explicit send buffer, NOT MPI_IN_PLACE (MS-MPI zeros the buffer for in-place reduce on this build)
sbuf = maxDiff; CALL MPI_ALLREDUCE(sbuf, maxDiff, 1, MPI_DOUBLE_PRECISION, MPI_MAX, MPI_COMM_PICLAS, iError)
sbuf = maxB   ; CALL MPI_ALLREDUCE(sbuf, maxB   , 1, MPI_DOUBLE_PRECISION, MPI_MAX, MPI_COMM_PICLAS, iError)
sbuf = matVol ; CALL MPI_ALLREDUCE(sbuf, matVol , 1, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_PICLAS, iError)
sbuf3 = matH  ; CALL MPI_ALLREDUCE(sbuf3, matH  , 3, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_PICLAS, iError)
sbuf3 = matHs ; CALL MPI_ALLREDUCE(sbuf3, matHs , 3, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_PICLAS, iError)
sbuf3 = matB  ; CALL MPI_ALLREDUCE(sbuf3, matB  , 3, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_COMM_PICLAS, iError)
#endif /*USE_MPI*/
SWRITE(UNIT_stdOut,'(A,ES12.5,A,ES12.5,A,F8.4)') ' | RSP correction: max|dB|=',maxDiff,'  max|B_free|=',maxB, &
    '  rel=',maxDiff/MAX(maxB,TINY(1.))
IF(matVol.GT.0.)THEN
  matH = matH/matVol; matHs = matHs/matVol; matB = matB/matVol
  SWRITE(UNIT_stdOut,'(A,ES12.5)')             ' | material region volume        =',matVol
  SWRITE(UNIT_stdOut,'(A,3(1X,ES13.5))')       ' | <H_s> in material  (A/m)      =',matHs
  SWRITE(UNIT_stdOut,'(A,3(1X,ES13.5))')       ' | <H>   in material  (A/m)      =',matH
  SWRITE(UNIT_stdOut,'(A,3(1X,ES13.5))')       ' | <B>   in material  (T)        =',matB
  IF(SUM(matHs**2).GT.0.)THEN
    ! Projection of <H> onto <H_s>: for a sphere in a uniform applied field this is the analytic 3/(mu_r+2)
    SWRITE(UNIT_stdOut,'(A,ES13.5)')           ' | <H>.<H_s>/|<H_s>|^2          =',DOT_PRODUCT(matH,matHs)/SUM(matHs**2)
  END IF
END IF

! Cleanup
DO iElem=1,nElems
  SDEALLOCATE(HsStore(iElem)%Hs)
  SDEALLOCATE(HsStore(iElem)%G)
  SDEALLOCATE(SoftIronRHSVol(iElem)%RHSvol)
END DO
DEALLOCATE(HsStore)
DEALLOCATE(SoftIronRHSVol)
DEALLOCATE(SoftIronQnFace)

SWRITE(UNIT_stdOut,'(A)') ' SOFT-IRON RSP CORRECTION DONE!'
SWRITE(UNIT_stdOut,'(132("-"))')
END SUBROUTINE SolveSoftIronRSP


!==================================================================================================================================
!> Internal-piclas-build entry point for the RSP correction, called from piclas_init.f90 right after InitHDG. No-op unless SuperB()
!> flagged the correction as pending (SoftIronRSPPending), which it only does when it ran before HDG was up.
!>
!> The standalone superB.exe sets chitens = mu_r BEFORE InitHDG, so its element matrices are the RSP operator and nothing has to be
!> undone. Here InitHDG has already baked the ELECTROSTATIC coefficient (1, or eps_r in dielectric regions) into Dhat/Ehat/Smat, and
!> the PIC run that follows needs exactly those matrices back. So this routine
!>   1. saves chitens and the HDG state (lambda, U_N%U, U_N%E),
!>   2. swaps chitens to mu_r and rebuilds the element matrices + preconditioner,
!>   3. runs the correction,
!>   4. restores chitens, rebuilds again, and restores the HDG state,
!> leaving the solver bit-for-bit in the condition InitHDG left it. Finally it performs the BGField h5 output and the magnet-array
!> clean-up that SuperB() skipped.
!==================================================================================================================================
SUBROUTINE SolveSoftIronRSPDeferred()
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_SuperB_Vars        ,ONLY: SoftIronRSPPending, DoCalcErrorNormsSuperB
USE MOD_SuperB_Vars        ,ONLY: PermanentMagnets, PermanentMagnetInfo
USE MOD_SuperB_Init        ,ONLY: SetChiTensFromMuR
USE MOD_Equation_Vars      ,ONLY: chi
USE MOD_Interpolation_Vars ,ONLY: N_BG
USE MOD_Mesh_Vars          ,ONLY: nElems, offSetElem, nSides, N_SurfMesh
USE MOD_DG_Vars            ,ONLY: N_DG_Mapping, U_N
USE MOD_HDG_Vars           ,ONLY: HDG_Surf_N, nGP_face
USE MOD_HDG_Vars           ,ONLY: iteration, iterationTotal, RunTime, RunTimeTotal, RunTimePerIteration, HDGNorm
USE MOD_Elem_Mat           ,ONLY: Elem_Mat
#if USE_PETSC
USE MOD_Elem_Mat           ,ONLY: PETScFillSystemMatrix
#else
USE MOD_Elem_Mat           ,ONLY: BuildPrecond
#endif /*USE_PETSC*/
USE MOD_HDF5_Output_Fields ,ONLY: WriteBGFieldToHDF5, WriteBGFieldAnalyticToHDF5
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER :: iElem, SideID, Nloc, NSide
! Backups taken over the RSP solve
TYPE tChiBak
  REAL,ALLOCATABLE :: tens(:,:,:,:,:), tensInv(:,:,:,:,:)
END TYPE tChiBak
TYPE tVolBak
  REAL,ALLOCATABLE :: U(:,:,:,:), E(:,:,:,:)
END TYPE tVolBak
TYPE tSurfBak
  REAL,ALLOCATABLE :: lambda(:,:)
END TYPE tSurfBak
TYPE(tChiBak) ,ALLOCATABLE :: ChiBak(:)
TYPE(tVolBak) ,ALLOCATABLE :: VolBak(:)
TYPE(tSurfBak),ALLOCATABLE :: SurfBak(:)
! CG convergence counters, so the RSP solve does not show up in the first FieldAnalyze row
INTEGER :: iterationBak, iterationTotalBak
REAL    :: RunTimeBak, RunTimeTotalBak, RunTimePerIterationBak, HDGNormBak
!==================================================================================================================================
IF(.NOT.SoftIronRSPPending) RETURN

! --- 1) Save chitens and the HDG state ------------------------------------------------------------------------------------------
ALLOCATE(ChiBak(1:nElems), VolBak(1:nElems), SurfBak(1:nSides))
DO iElem = 1, nElems
  Nloc = N_DG_Mapping(2,iElem+offSetElem)
  ALLOCATE(ChiBak(iElem)%tens(   1:3,1:3,0:Nloc,0:Nloc,0:Nloc)); ChiBak(iElem)%tens    = chi(iElem)%tens
  ALLOCATE(ChiBak(iElem)%tensInv(1:3,1:3,0:Nloc,0:Nloc,0:Nloc)); ChiBak(iElem)%tensInv = chi(iElem)%tensInv
  ALLOCATE(VolBak(iElem)%U(PP_nVar,0:Nloc,0:Nloc,0:Nloc))      ; VolBak(iElem)%U       = U_N(iElem)%U
  ALLOCATE(VolBak(iElem)%E(1:3    ,0:Nloc,0:Nloc,0:Nloc))      ; VolBak(iElem)%E       = U_N(iElem)%E
END DO ! iElem
DO SideID = 1, nSides
  NSide = N_SurfMesh(SideID)%NSide
  ALLOCATE(SurfBak(SideID)%lambda(PP_nVar,nGP_face(NSide)))    ; SurfBak(SideID)%lambda = HDG_Surf_N(SideID)%lambda
END DO ! SideID
iterationBak      = iteration     ; iterationTotalBak      = iterationTotal
RunTimeBak        = RunTime       ; RunTimeTotalBak        = RunTimeTotal
RunTimePerIterationBak = RunTimePerIteration               ; HDGNormBak = HDGNorm

! --- 2) Switch the HDG operator to div(mu_r grad .) ------------------------------------------------------------------------------
CALL SetChiTensFromMuR()
CALL Elem_Mat(0_i8)
#if USE_PETSC
CALL PETScFillSystemMatrix()
#else
CALL BuildPrecond()
#endif /*USE_PETSC*/

! --- 3) The actual correction ----------------------------------------------------------------------------------------------------
CALL SolveSoftIronRSP()

! --- 4) Restore the electrostatic operator and the HDG state ---------------------------------------------------------------------
DO iElem = 1, nElems
  chi(iElem)%tens    = ChiBak(iElem)%tens
  chi(iElem)%tensInv = ChiBak(iElem)%tensInv
END DO ! iElem
CALL Elem_Mat(0_i8)
#if USE_PETSC
CALL PETScFillSystemMatrix()
#else
CALL BuildPrecond()
#endif /*USE_PETSC*/
DO iElem = 1, nElems
  U_N(iElem)%U = VolBak(iElem)%U
  U_N(iElem)%E = VolBak(iElem)%E
  DEALLOCATE(ChiBak(iElem)%tens, ChiBak(iElem)%tensInv, VolBak(iElem)%U, VolBak(iElem)%E)
END DO ! iElem
DO SideID = 1, nSides
  HDG_Surf_N(SideID)%lambda = SurfBak(SideID)%lambda
  DEALLOCATE(SurfBak(SideID)%lambda)
END DO ! SideID
DEALLOCATE(ChiBak, VolBak, SurfBak)
iteration      = iterationBak     ; iterationTotal      = iterationTotalBak
RunTime        = RunTimeBak       ; RunTimeTotal        = RunTimeTotalBak
RunTimePerIteration = RunTimePerIterationBak              ; HDGNorm = HDGNormBak
SWRITE(UNIT_stdOut,'(A)') ' | Soft-iron: HDG chitens and solver state restored to the electrostatic problem.'

! --- 5) The output and clean-up that SuperB() left to us -------------------------------------------------------------------------
SoftIronRSPPending = .FALSE.
CALL WriteBGFieldToHDF5()
IF(DoCalcErrorNormsSuperB) CALL WriteBGFieldAnalyticToHDF5()
DO iElem = 1, nElems
  SDEALLOCATE(N_BG(iElem)%PsiMag)
END DO ! iElem
SDEALLOCATE(PermanentMagnets)
SDEALLOCATE(PermanentMagnetInfo)

END SUBROUTINE SolveSoftIronRSPDeferred

#endif /*USE_SUPER_B && USE_HDG*/
END MODULE MOD_SuperB_SoftIron
