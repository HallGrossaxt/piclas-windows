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
!===================================================================================================================================
!> Contains global variables used by the HDG modules.
!===================================================================================================================================
MODULE MOD_HDG_Vars
! MODULES
#if USE_MPI
USE mpi_f08
USE MOD_Globals
#endif /*USE_MPI*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
#if USE_HDG
INTEGER,ALLOCATABLE :: nGP_vol(:)  !< =(PP_N+1)**3
INTEGER,ALLOCATABLE :: nGP_face(:) !< =(PP_N+1)**2

LOGICAL             :: useHDG=.FALSE.
LOGICAL             :: ExactLambda =.FALSE.   !< Flag to initialize exact function for lambda
LOGICAL             :: UseNSideMin =.FALSE.   !< Flag to use NSideMin instead of NSideMax for the sides

! HDG volume variables
TYPE, PUBLIC :: HDG_Vol_N_Type
  REAL,ALLOCATABLE    :: Ehat(:,:,:)          !< Ehat matrix (nGP_Face,nGP_vol,6sides,nElems)
  REAL,ALLOCATABLE    :: InvDhat(:,:)         !< Inverse of Dhat matrix (nGP_vol,nGP_vol,nElems)
  REAL,ALLOCATABLE    :: JwGP_vol(:)          !< 3D quadrature weights*Jacobian for all elements
  REAL,ALLOCATABLE    :: RHS_vol(:,:)         !< Source RHS
  REAL,ALLOCATABLE    :: Smat(:,:,:,:)        !< side to side matrix, (ngpface, ngpface, 6sides, 6sides, nElems)
  REAL,ALLOCATABLE    :: NonlinVolumeFac(:)   !< Factor for Volumeintegration necessary for nonlinear sources
END TYPE HDG_Vol_N_Type

TYPE(HDG_Vol_N_Type),ALLOCATABLE :: HDG_Vol_N(:)      !<

! --- Element-major copy of Smat for the CG MatVec (performance only: same values, permuted index order) ---
! Per element the trace MatVec is exactly one dense product of size nElemDOF = 6*nGP_face. HDG_Vol_N(iElem)%Smat
! stores it as 36 separate (nGP_face x nGP_face) blocks with index order (i,j,jLocSide,locSideID), which is NOT
! the memory order of that dense matrix -- the strides of j and jLocSide are swapped. SmatE holds the same
! numbers permuted into row=(i,jLocSide), col=(j,locSideID), so the whole element MatVec becomes one contiguous
! nElemDOF x nElemDOF product instead of 36 tiny ones. Smat itself is left untouched and is still the array the
! preconditioner, the PETSc assembly and hdg_linear read.
LOGICAL             :: ElemMajorMatVecWanted = .TRUE. !< read-in switch HDGElemMajorMatVec (A/B testing; .FALSE. forces side-major)
LOGICAL             :: UseElemMajorMatVec = .FALSE. !< .TRUE. when the fast path is both wanted and applicable (set in Elem_Mat)
INTEGER             :: nElemDOF_EM = 0             !< 6*nGP_face(Nloc), the element trace-block size (uniform N only)
REAL,ALLOCATABLE    :: SmatE(:,:,:)                !< (nElemDOF_EM,nElemDOF_EM,PP_nElems) element-major Smat
INTEGER,ALLOCATABLE :: ElemMatVecPass(:)           !< 1:PP_nElems, 1 = element has no MPIsides_YOUR side and can be
                                                   !< done before FinishExchange, 2 = must wait for the halo lambda

! HDG side variables
TYPE HDG_Surf_N_Type
  ! lambda, mv, R, V, Z are NOT separately allocated: they are contiguous windows into the flat
  ! TraceFlat_* arrays below (see AllocateTraceVectors in hdg.f90). Keeping them as components means
  ! every consumer outside the CG hot loops -- mortars, the MPI exchange, the BCs, FPC, the state I/O --
  ! is unchanged, while the CG itself walks one long contiguous array instead of nSides heap blocks.
  ! CONTIGUOUS matters: without it the compiler must assume a strided target and copies to a temporary
  ! whenever one of these is passed to an assumed-shape dummy or to MPI.
  REAL,POINTER,CONTIGUOUS :: lambda(:,:)      !< lambda, ((NSideMin+1)^2,nSides) where NSideMin is the minimum of the two faces
  REAL,ALLOCATABLE    :: Precond(:,:)         !< block diagonal preconditioner for lambda(nGP_face, nGP-face, nSides)
  REAL,ALLOCATABLE    :: InvPrecondDiag(:)    !< 1/diagonal of Precond
  REAL,ALLOCATABLE    :: qn_face(:,:)         !< for Neumann BC
  REAL,ALLOCATABLE    :: RHS_face(:,:)        !<
  REAL,POINTER,CONTIGUOUS :: mv(:,:)          !<
  REAL,POINTER,CONTIGUOUS :: R(:,:)           !<
  REAL,POINTER,CONTIGUOUS :: V(:,:)           !<
  REAL,POINTER,CONTIGUOUS :: Z(:,:)           !<
  REAL,ALLOCATABLE    :: FPCz(:,:)            !< (1:nUniqueFPCBounds,nGP_face) cached A_nn^-1 * C_k per side
                                              !< (FPC-via-CG / capacitance-matrix path only; ragged like lambda)
#if USE_MPI
  REAL,ALLOCATABLE    :: buf(:,:)
  REAL,ALLOCATABLE    :: buf2(:,:)
#endif
END TYPE HDG_Surf_N_Type

! DG solution (JU or U) vectors)
TYPE(HDG_Surf_N_Type),ALLOCATABLE :: HDG_Surf_N(:) !< Solution variable for each equation, node and element,

! --- Flat storage behind the five CG trace vectors ---------------------------------------------
! HDG_Surf_N(s)%lambda/mv/R/V/Z are windows into these. Side s occupies
! TraceOff(s)+1 : TraceOff(s+1), i.e. PP_nVar*nGP_face(NSide(s)) reals, so p-adaption and mortars
! (ragged side sizes) are handled by the offset table rather than by a uniform stride.
! The CG dot products and axpy updates run over TraceLen contiguous reals in one loop; previously
! they were nSides separate loops of 4 reals each, one heap block per side.
REAL,ALLOCATABLE,TARGET :: TraceFlatLambda(:) !< backing store for %lambda
REAL,ALLOCATABLE,TARGET :: TraceFlatMv(:)     !< backing store for %mv
REAL,ALLOCATABLE,TARGET :: TraceFlatR(:)      !< backing store for %R
REAL,ALLOCATABLE,TARGET :: TraceFlatV(:)      !< backing store for %V
REAL,ALLOCATABLE,TARGET :: TraceFlatZ(:)      !< backing store for %Z
INTEGER,ALLOCATABLE :: TraceOff(:)            !< [1:nSides+1] start offsets, TraceOff(1)=0
INTEGER             :: TraceLen=0             !< total length = TraceOff(nSides+1)
INTEGER             :: TraceLenInner=0        !< length excluding the nMPIsides_YOUR tail, i.e. the
                                              !< range the dot products must reduce over (YOUR sides
                                              !< are owned by another rank and must not be counted)

REAL,ALLOCATABLE    :: Tau(:)                 !< Stabilization parameter, per element
REAL,ALLOCATABLE    :: lambdaLB(:,:,:)        !< lambda, ((PP_N+1)^2,nSides)
INTEGER,ALLOCATABLE :: iLocSides(:,:)         !< iLocSides, ((PP_N+1)^2,nSides) - used for I/O and ALLGATHERV of lambda
REAL,ALLOCATABLE    :: qn_face_MagStat(:,:,:) !< for Neumann BC
! --- superB soft-iron reduced-scalar-potential (RSP) source of div(mu_r grad Psi) = div(G), G = mu_r H_s + M ---
! The RSP source enters the HDG system in two places (see MOD_SuperB_SoftIron for the derivation):
!   u-system   (element-local): the strong volume source -int( (div G) v )      -> SoftIronRHSVol
!   lambda-system (trace eq.) : the flux int( (G.n_out) mu ) on every face      -> SoftIronQnFace
! The second term carries the material/magnet interface jump [[G.n]] and is what makes soft iron magnetise.
LOGICAL             :: UseSoftIronRSP = .FALSE. !< when .TRUE., HDGLinear adds the two SoftIron* contributions to the RHS
TYPE tSoftIronVol
  REAL,ALLOCATABLE  :: RHSvol(:)                !< strong volume source -JwGP*div(G) per volume DOF r [1:nGP_vol(Nloc)]
END TYPE tSoftIronVol
TYPE(tSoftIronVol),ALLOCATABLE :: SoftIronRHSVol(:) !< [1:PP_nElems], filled by MOD_SuperB_SoftIron before the RSP solve
REAL,ALLOCATABLE    :: SoftIronQnFace(:,:)      !< [1:nGP_face(NMax),1:nSides] sum over adjacent elements of
                                                !< (G.n_out)*SurfElem*wGP*wGP, i.e. the Neumann-style interface/boundary flux
INTEGER             :: nDirichletBCSides
INTEGER             :: nNeumannBCsides
INTEGER             :: nConductorBCsides      !< Number of processor-local sides that are conductors (FPC) in [1:nBCSides]
INTEGER             :: nDistriCapBCsides      !< Number of processor-local sides that are distributed capacitance (DC) in [1:nBCSides]
INTEGER             :: ZeroPotentialSide      !< (local) SideID of the side where the potential of one DOF is set to zero
INTEGER,ALLOCATABLE :: ConductorBC(:)
INTEGER,ALLOCATABLE :: DirichletBC(:)
INTEGER,ALLOCATABLE :: NeumannBC(:)
INTEGER,ALLOCATABLE :: DistriCapBC(:)
LOGICAL             :: HDGnonlinear           !< Use non-linear sources for HDG? (e.g. Boltzmann electrons)
LOGICAL             :: NewtonExactSourceDeriv
LOGICAL             :: NewtonAdaptStartValue
INTEGER             :: AdaptIterNewton
INTEGER             :: AdaptIterNewtonToLinear
INTEGER             :: AdaptIterNewtonOld
INTEGER             :: HDGNonLinSolver        !< 1 Newton, 2 Fixpoint
!mappings
INTEGER             :: sideDir(6),pm(6),dirPm2iSide(2,3)
!CG parameters
INTEGER             :: PrecondType=0          !< 0: none 1: block diagonal 2: only diagonal 3:Identity, debug
INTEGER             :: MaxIterCG
INTEGER             :: MaxIterNewton
INTEGER             :: OutIterCG
REAL                :: EpsCG,EpsNonLinear
LOGICAL             :: UseRelativeAbortCrit
LOGICAL             :: HDGInitIsDone=.FALSE.
INTEGER             :: HDGSkip, HDGSkipInit
REAL                :: HDGSkip_t0
INTEGER,ALLOCATABLE :: MaskedSide(:)          !< 1:nSides: all sides which are set to zero in matvec
! --- Phase 5: additive two-level coarse correction (deflation by unsmoothed geometric aggregation) ---
! The block-Jacobi / diagonal preconditioner is purely local, so it does nothing for the low-frequency
! error modes that make the CG count scale ~1/h (measured: none 5539 -> diagonal 3932 -> block-Jacobi
! 3941 iterations on the magnetron bench; the local preconditioner is nearly irrelevant). A coarse
! space W (piecewise-constant over a coarse grid of side aggregates) captures exactly those modes.
! Used as an ADDITIVE second level, M^-1 r = M_local^-1 r + W E^-1 W^T r with E = W^T A W: this is SPD
! for any SPD E, so the CG driver is unchanged and correctness holds even if E is stale (only the
! iteration reduction degrades). Flag-gated, default OFF.
LOGICAL             :: UseCoarseCorrection = .FALSE. !< read-in switch HDGCoarseCorrection
INTEGER             :: nCoarseTarget = 16       !< read-in HDGnCoarse: target aggregates along the widest dim
INTEGER             :: nCoarse = 0              !< actual number of aggregates m (product of per-dim bin counts)
INTEGER,ALLOCATABLE :: SideToAgg(:)            !< [1:nSides] aggregate id 1..nCoarse, or 0 if the side is
                                               !< excluded (Dirichlet, masked, or MPIsides_YOUR)
REAL,ALLOCATABLE    :: CoarseChol(:,:)         !< [nCoarse,nCoarse] Cholesky factor U of E = W^T A W (E=U^T U)
LOGICAL             :: CoarseValid = .FALSE.   !< E has been built and factorised for the current operator
!mortar variables
INTEGER,ALLOCATABLE :: SmallMortarInfo(:)     !< 1:nSides: info on small Mortar sides:
                                              !< -1: is neighbor small mortar , 0: not a small mortar, 1: small mortar on big side
LOGICAL             :: HDGDisplayConvergence  !< Display divergence criteria: Iterations, Runtime and Residual

! --- CG phase profiling (diagnostic only; accumulated per solve, reported by DisplayConvergence) ---
! A CG iteration is one MatVec + three dot products (each an MPI_ALLREDUCE) + a BCAST + one
! preconditioner apply + two vector updates. Everything except the MatVec walks the per-side
! HDG_Surf_N components, so this split is what decides whether flattening those is worth it.
INTEGER,PARAMETER   :: nCGPhase = 6         !< 1 MatVec, 2 dot(V,Z), 3 axpy lambda/R, 4 dot(R,R)+BCAST,
                                            !< 5 preconditioner, 6 dot(R,Z)+update V
LOGICAL             :: HDGProfileCG=.FALSE. !< Read-in switch HDGProfileCG: time the CG phases and print the split
REAL                :: CGPhaseTime(nCGPhase)!< Accumulated seconds per phase for the current solve
REAL                :: RunTime                !< CG Solver runtime
REAL                :: RunTimePerIteration    !< CG Solver runtime per iteration
REAL                :: HDGNorm                !< Norm
INTEGER             :: iteration              !< number of iterations to achieve the norm
INTEGER             :: iterationTotal         !< number of iterations over the course of a time step (possibly multiple stages)
REAL                :: RunTimeTotal           !< CG Solver runtime sum over the course of a time step (possibly multiple stages)

! --- Boltzmann relation (BR) electron fluid
LOGICAL               :: UseBRElectronFluid            !< Indicates usage of BR electron fluid model
INTEGER               :: BRNbrOfRegions                !< Nbr of regions to be mapped to Elems
LOGICAL               :: CalcBRVariableElectronTemp    !< Use variable ref. electron temperature for BR electron fluid
CHARACTER(255)        :: BRVariableElectronTemp        !< Variable electron reference temperature when using Boltzmann relation
                                                       !< electron model (default is using a constant temperature)
REAL                  :: BRVariableElectronTempValue   !< Final electron temperature
INTEGER, ALLOCATABLE  :: ElemToBRRegion(:)             !< ElemToBRRegion(1:nElems)
REAL, ALLOCATABLE     :: BRRegionBounds(:,:)           !< BRRegionBounds ((xmin,xmax,ymin,...)|1:BRNbrOfRegions)
REAL, ALLOCATABLE     :: RegionElectronRef(:,:)        !< RegionElectronRef((rho0[C/m^3],phi0[V],Te[eV])|1:BRNbrOfRegions)
REAL, ALLOCATABLE     :: RegionElectronRefBackup(:,:)  !< RegionElectronRefBackup(rho0[C/m^3],phi0[V],Te[eV])|1:BRNbrOfRegions) when using variable
                                                       !< reference electron temperature
REAL                  :: BRTimeStepMultiplier          !< Factor that is multiplied with the ManualTimeStep when using BR model
REAL                  :: BRTimeStepBackup              !< Original time step
LOGICAL               :: BRAutomaticElectronRef        !< Automatically obtain the reference parameters (from a fully kinetic
                                                       !< simulation), store them in .h5 state and in .csv
INTEGER               :: nBRAverageElems               !< Processor local number of elements in which the reference values are averaged
INTEGER               :: nBRAverageElemsGlobal         !< Global number of elements in which the reference values are averaged
INTEGER, ALLOCATABLE  :: BRAverageElemToElem(:)        !< Mapping BR average elem to processo-local elem
#if defined(PARTICLES)
! --- Switching between BR and fully kinetic HDG
LOGICAL               :: BRConvertElectronsToFluid     !< User variable for removing all electrons and using BR instead
REAL                  :: BRConvertElectronsToFluidTime !< Time when kinetic electrons should be converted to BR fluid electrons
LOGICAL               :: BRConvertFluidToElectrons     !< User variable for creating particles from BR electron fluid (uses
REAL                  :: BRConvertFluidToElectronsTime !< Time when BR fluid electrons should be converted to kinetic electrons
INTEGER               :: BRConvertMode                 !< Mode used for switching BR->kin->BR OR kin->BR->kin
                                                       !< and ElectronDensityCell ElectronTemperatureCell from .h5 state file)
LOGICAL               :: BRConvertModelRepeatedly      !< Repeat the switch between BR and kinetic multiple times
LOGICAL               :: BRElectronsRemoved            !< True if electrons were removed during restart (only BR electrons)
REAL                  :: DeltaTimeBRWindow             !< Time length when BR is active (possibly multiple times)
LOGICAL               :: BRNullCollisionDefault        !< Flag (backup of read-in parameter) whether null collision method
                                                       !< (determining number of pairs based on maximum relaxation frequency) is used
#endif /*defined(PARTICLES)*/

! --- Sub-communicator groups

#if USE_MPI
TYPE tMPIGROUP
  INTEGER                     :: ID                     !< MPI communicator ID
  TYPE(MPI_comm)              :: UNICATOR=MPI_COMM_NULL !< MPI communicator for floating boundary condition
  INTEGER                     :: nProcs                 !< number of MPI processes part of the FPC group
  INTEGER                     :: nProcsWithSides        !< number of MPI processes part of the FPC group and actual FPC sides
  INTEGER                     :: MyRank                 !< MyRank within communicator
END TYPE tMPIGROUP
#endif /*USE_MPI*/

!===================================================================================================================================
!-- Floating boundary condition
!===================================================================================================================================

LOGICAL                       :: UseFPC             !< Automatic flag when FPCs are active

TYPE tFPC
  REAL,ALLOCATABLE            :: Voltage(:)         !< Electric potential on floating boundary condition for each (required) BC index over all processors. This is the value that is reduced to the MPI root process
  REAL,ALLOCATABLE            :: VoltageProc(:)     !< Electric potential on floating boundary condition for each (required) BC index for a single processor. This value is non-zero only when the processor has an actual FPC side
  REAL,ALLOCATABLE            :: Charge(:)          !< Accumulated charge on floating boundary condition for each (required) BC index over all processors
  REAL,ALLOCATABLE            :: ChargeProc(:)      !< Accumulated charge on floating boundary condition for each (required) BC index for a single processor
#if USE_MPI
  TYPE(tMPIGROUP),ALLOCATABLE :: COMM(:)            !< communicator and ID for parallel execution
#endif /*USE_MPI*/
  !INTEGER                     :: NBoundaries       !< Total number of boundaries where the floating boundary condition is evaluated
  INTEGER                     :: nFPCBounds         !< Global number of boundaries that are FPC with BCType=20 in [1:nBCs],
!                                                   !< they might belong to the same group (electrically connected)
  INTEGER                     :: nUniqueFPCBounds   !< Global number of independent FPC after grouping certain BC sides together
!                                                   !< (electrically connected) with the same BCState ID
  INTEGER,ALLOCATABLE         :: BCState(:)         !< BCState of the i-th FPC index
  !INTEGER,ALLOCATABLE         :: BCIDToFPCBCID(:)  !< Mapping BCID to FPC BCID (1:nPartBound)
  INTEGER,ALLOCATABLE         :: Group(:,:)         !< FPC%Group(1:FPC%nFPCBounds,3)
                                                    !<   1: BCState
                                                    !<   2: iUniqueFPC (i-th FPC group ID)
                                                    !<   3: number of BCSides for each FPC group
  INTEGER,ALLOCATABLE         :: GroupGlobal(:)     !< Sum of nSides associated with each i-th FPC boundary
  LOGICAL,ALLOCATABLE         :: BConProc(:)        !< True, if iUniqueFPCBC is on current process
END TYPE tFPC

TYPE(tFPC)   :: FPC

! --- FPC without PETSc: solve the bordered system in the internal CG via a capacitance matrix (Woodbury).
!     Active only in non-PETSc builds when FPCs are present (set in InitFPC). See scope_fpc_cg_magnetron.md.
LOGICAL              :: UseFPCviaCG = .FALSE. !< Carry FPC in the internal CG (no PETSc) via the capacitance matrix
REAL,ALLOCATABLE     :: FPCcap(:,:)           !< S (nUniqueFPCBounds x nUniqueFPCBounds) capacitance matrix, S = D - C^T A_nn^-1 C
REAL,ALLOCATABLE     :: FPCcapInv(:,:)        !< S^-1 (nUniqueFPCBounds x nUniqueFPCBounds)
LOGICAL              :: FPCcapValid = .FALSE. !< FPCz/FPCcap are valid for the current A; invalidate on A-change (load balance, dt)
LOGICAL              :: FPCMaskConductor = .TRUE. !< When UseFPCviaCG: mask conductor faces (A_nn) in MatVec/EvalResidual.
                                              !< Coupling routines toggle this .FALSE. to form C/D/C^T y with the unmasked operator.

!===================================================================================================================================
!-- Electric Potential Condition (for decharging)
!===================================================================================================================================

LOGICAL                       :: UseEPC             !< Automatic flag when EPCs are active

TYPE tEPC
  REAL,ALLOCATABLE            :: Voltage(:)         !< Electric potential on floating boundary condition for each (required) BC index over all processors. This is the value that is reduced to the MPI root process
  REAL,ALLOCATABLE            :: VoltageProc(:)     !< Electric potential on floating boundary condition for each (required) BC index for a single processor. This value is non-zero only when the processor has an actual EPC side
  REAL,ALLOCATABLE            :: Charge(:)          !< Accumulated charge on floating boundary condition for each (required) BC index over all processors
  REAL,ALLOCATABLE            :: ChargeProc(:)      !< Accumulated charge on floating boundary condition for each (required) BC index for a single processor
  REAL,ALLOCATABLE            :: Resistance(:)      !< Vector (length corresponds to the number of EPC boundaries) with the resistance for each EPC in Ohm
#if USE_MPI
  TYPE(tMPIGROUP),ALLOCATABLE :: COMM(:)            !< communicator and ID for parallel execution
#endif /*USE_MPI*/
  !INTEGER                     :: NBoundaries       !< Total number of boundaries where the floating boundary condition is evaluated
  INTEGER                     :: nEPCBounds         !< Global number of boundaries that are EPC with BCType=20 in [1:nBCs],
!                                                   !< they might belong to the same group (electrically connected)
  INTEGER                     :: nUniqueEPCBounds   !< Global number of independent EPC after grouping certain BC sides together
!                                                   !< (electrically connected) with the same BCState ID
  INTEGER,ALLOCATABLE         :: BCState(:)         !< BCState of the i-th EPC index
  !INTEGER,ALLOCATABLE         :: BCIDToEPCBCID(:)  !< Mapping BCID to EPC BCID (1:nPartBound)
  INTEGER,ALLOCATABLE         :: Group(:,:)         !< EPC%Group(1:EPC%nEPCBounds,3)
                                                    !<   1: BCState
                                                    !<   2: iUniqueEPC (i-th EPC group ID)
                                                    !<   3: number of BCSides for each EPC group
  INTEGER,ALLOCATABLE         :: GroupGlobal(:)     !< Sum of nSides associated with each i-th EPC boundary
END TYPE tEPC

TYPE(tEPC)   :: EPC
#if defined(PARTICLES)
!===================================================================================================================================
!-- Coupled Power Potential (CPP)
!-- Special BC with floating potential that is defined by the absorbed power of the charged particles
!===================================================================================================================================

LOGICAL           :: UseCoupledPowerPotential !< Switch calculation on/off
INTEGER,PARAMETER :: CPPDataLength=6          !< Number of variables in BVData

#if USE_MPI
TYPE(tMPIGROUP) :: CPPCOMM       !< communicator and ID for parallel execution
#endif /*USE_MPI*/

REAL    :: CoupledPowerPotential(CPPDataLength) !< (/min, start, max/) electric potential, e.g., used at all BoundaryType = (/2,2/)
REAL    :: CoupledPowerTarget                   !< Target input power at all BoundaryType = (/2,2/)
REAL    :: CoupledPowerRelaxFac                 !< Relaxation factor for calculation of new electric potential
REAL    :: CoupledPowerFrequency                !< Frequency with which the integrated power is calculated (must be consistent Part-AnalyzeStep, i.e., that one cycle with period T=1/f must be larger than Part-AnalyzeStep * dt)
INTEGER :: CoupledPowerMode                     !< Method for power adjustment with 1: instantaneous power, 2: moving average power, 3: integrated power
LOGICAL :: CoupledPowerPulsed                    !< T: CPP AC electrodes (ExactFunc -1) use a bipolar SQUARE wave instead of cos
                                                 !<    (HiPIMS/pulsed-magnetron; two electrodes at phase 0 and pi give anti-phase cathode/anode)
REAL    :: CoupledPowerPulseDuty                 !< Fraction of the period at the +amplitude level for the pulsed wave (0..1, default 0.5 = symmetric)

!===================================================================================================================================
!-- Bias Voltage (for calculating a BC voltage bias for certain BCs)
!===================================================================================================================================

LOGICAL           :: UseBiasVoltage !< Automatic flag when bias voltage is to be used
INTEGER,PARAMETER :: BVDataLength=3 !< Number of variables in BVData

TYPE tBV
#if USE_MPI
  TYPE(tMPIGROUP)     :: COMM                 !< communicator and ID for parallel execution
#endif /*USE_MPI*/
  INTEGER             :: NPartBoundaries      !< Total number of boundaries where the particles are counted
  INTEGER,ALLOCATABLE :: PartBoundaries(:)    !< Part-boundary number on which the particles are counted
  REAL                :: Frequency            !< Adaption nrequency with which the bias voltage is adjusted (every period T = 1/f the bias voltage is changed)
  REAL                :: Delta                !< Voltage difference used to change the current bias voltage (may also be adjusted over time automatically)
  REAL                :: BVData(BVDataLength) !< 1: bias voltage
!                                             !< 2: Ion excess
!                                             !< 3: sim. time when next adjustment happens
END TYPE tBV

TYPE(tBV)   :: BiasVoltage
#endif /*defined(PARTICLES)*/
!===================================================================================================================================

#endif /*USE_HDG*/
END MODULE MOD_HDG_Vars