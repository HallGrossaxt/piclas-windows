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

MODULE MOD_SuperB_Init
!===================================================================================================================================
!>
!===================================================================================================================================
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
PUBLIC :: InitializeSuperB, DefineParametersSuperB, FinalizeSuperB
#if USE_HDG
PUBLIC :: InitMagneticMaterials, SetChiTensFromMuR
#endif /*USE_HDG*/
!===================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters for SuperB
!==================================================================================================================================
SUBROUTINE DefineParametersSuperB()
! MODULES
USE MOD_Globals
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection('SuperB')

CALL prms%CreateLogicalOption('DoCalcErrorNormsSuperB', 'Set true to compute L2 and LInf error norms for magnetic fields.','.FALSE.')
CALL prms%CreateIntOption(    'NAnalyze'              , 'Polynomial degree at which analysis is performed (e.g. for L2 errors).\n'//&
                                                        'Default: 2*N.')
CALL prms%CreateLogicalOption('PIC-CalcBField-OutputVTK', 'Output of the magnets/coils geometry as separate VTK files','.FALSE.')

! Input of permanent magnets
CALL prms%SetSection('Input of permanent magnets')
CALL prms%CreateIntOption(      'NumOfPermanentMagnets'             , 'Number of permanent magnets','0')
CALL prms%CreateStringOption(   'PermanentMagnet[$]-Type'           , 'Permanent magnet type: cuboid, sphere, cylinder, conic', &
                                                                      numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('PermanentMagnet[$]-BasePoint'      , 'Origin (vector) for geometry parametrization', &
                                                                      numberedmulti=.TRUE., no=3)
CALL prms%CreateIntOption(      'PermanentMagnet[$]-NumNodes'       , 'Number of Gauss points for the discretization of the '//&
                                                                      'permanent magnet:\n'//&
                                                                      'Cuboid: N points in each direction (total number: 6N^2)\n'//&
                                                                      'Sphere: N divisions in the zenith direction with 2*N '//&
                                                                      'points in the azimuthal direction\n'//&
                                                                      'Cylinder: N divisions along height vector, 2*N points in '//&
                                                                      'the azimuthal direction, N points in radial direction on '//&
                                                                      'the top and bottom face\n'//&
                                                                      'Conic: see the cylinder NumNodes description', &
                                                                      numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('PermanentMagnet[$]-Magnetisation'  , 'Magnetisation vector in [A/m]', numberedmulti=.TRUE., no=3)
CALL prms%CreateRealArrayOption('PermanentMagnet[$]-BaseVector1'    , 'Vector 1 spanning the cuboid', numberedmulti=.TRUE., no=3)
CALL prms%CreateRealArrayOption('PermanentMagnet[$]-BaseVector2'    , 'Vector 2 spanning the cuboid', numberedmulti=.TRUE., no=3)
CALL prms%CreateRealArrayOption('PermanentMagnet[$]-BaseVector3'    , 'Vector 3 spanning the cuboid', numberedmulti=.TRUE., no=3)
CALL prms%CreateRealOption(     'PermanentMagnet[$]-Radius'         , 'Radius of a spheric, cylindric and conic (first radius) '//&
                                                                      'permanent magnet', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(     'PermanentMagnet[$]-Radius2'        , 'Radius of the second radius of the conic permanent magnet'//&
                                                                      ' or inner radius for hollow cylinders', &
                                                                      numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('PermanentMagnet[$]-HeightVector'   , 'Height vector of cylindric and conic permanent magnet', &
                                                                      numberedmulti=.TRUE., no=3)

! Input of coils
CALL prms%SetSection('Input of coils')
CALL prms%CreateIntOption(      'NumOfCoils'            , 'Number of coils','0')
CALL prms%CreateStringOption(   'Coil[$]-Type'          , 'Coil type: custom, circle, rectangular, linear conductor (straight '//&
                                                          'wire)', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('Coil[$]-BasePoint'     , 'Origin vector of the coil/linear conductor', numberedmulti=.TRUE., no=3)
CALL prms%CreateRealArrayOption('Coil[$]-LengthVector'  , 'Length vector of the coil/linear conductor, normal to the cross-'//&
                                                          'sectional area', numberedmulti=.TRUE., no=3)
CALL prms%CreateRealOption(     'Coil[$]-Current'       , 'Electrical coil current [A]', numberedmulti=.TRUE.)

! Linear conductor (calculated from the number of loops and points per loop for coils)
CALL prms%CreateIntOption(      'Coil[$]-NumNodes'      , 'Number of nodes for a linear conductor' &
                                                        , numberedmulti=.TRUE.)
! Coils
CALL prms%CreateIntOption(      'Coil[$]-LoopNum'       , 'Number of coil loops', numberedmulti=.TRUE.)
CALL prms%CreateIntOption(      'Coil[$]-PointsPerLoop' , 'Number of points per loop (azimuthal discretization)', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('Coil[$]-AxisVec1'      , 'Axial vector defines the orientation of the cross-section together '//&
                                                          'with the length vector', numberedmulti=.TRUE., no=3)
! Custom coils
CALL prms%SetSection('Custom coils')
CALL prms%CreateIntOption(      'Coil[$]-NumOfSegments' , 'Number of segments for the custom coil definition', numberedmulti=.TRUE.)
CALL prms%CreateStringOption(   'Coil[$]-Segment[$]-SegmentType'  , 'Possible segment types: line or circle', numberedmulti=.TRUE.)
CALL prms%CreateIntOption(      'Coil[$]-Segment[$]-NumOfPoints'  , 'Number of points to discretize the segment', &
                                                                    numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('Coil[$]-Segment[$]-LineVector'   , 'Line segment: Vector (x,y) in the cross-sectional plane '//&
                                                                    'defined by the length and axial vector', numberedmulti=.TRUE., no=2)
CALL prms%CreateRealOption(     'Coil[$]-Segment[$]-Radius'       , 'Circle segment: Radius in the cross-sectional plane '//&
                                                                    'defined by the length and axial vector', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(     'Coil[$]-Segment[$]-Phi1'         , 'Circle segment: Initial angle in [deg]', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(     'Coil[$]-Segment[$]-Phi2'         , 'Circle segment: Final angle in [deg]', numberedmulti=.TRUE.)

! Circle coils
CALL prms%CreateRealOption(     'Coil[$]-Radius'        , 'Radius for circular coils', numberedmulti=.TRUE.)

! Rectangle coils
CALL prms%CreateRealArrayOption('Coil[$]-RectVec1'      , 'Vector 1 (x,y) in the cross-sectional plane defined by the length '//&
                                                          'and axial vector, spanning the rectangular coil', numberedmulti=.TRUE., no=2)
CALL prms%CreateRealArrayOption('Coil[$]-RectVec2'      , 'Vector 2 (x,y) in the cross-sectional plane defined by the length '//&
                                                          'and axial vector, spanning the rectangular coil', numberedmulti=.TRUE., no=2)

! Time-dependent coils
CALL prms%SetSection('Time-dependent coils')
CALL prms%CreateLogicalOption(  'Coil[$]-TimeDepCoil'     , 'Use time-dependent current (sinusoidal curve) for coil', &
                                                            '.FALSE.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(     'Coil[$]-CurrentFrequency', 'Current frequency [1/s]', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(     'Coil[$]-CurrentPhase'    , 'Current phase shift [rad]','0.', numberedmulti=.TRUE.)
CALL prms%CreateIntOption(      'nTimePoints'             , 'Number of points for the discretization of the sinusoidal curve')

! Input of soft-magnetic materials (linear mu_r>1) for the reduced-scalar-potential (RSP) soft-iron correction
CALL prms%SetSection('Input of soft-magnetic materials')
CALL prms%CreateIntOption(      'NumOfMagneticMaterials'          , 'Number of soft-magnetic (mu_r>1) material regions','0')
CALL prms%CreateRealOption(     'MagneticMaterial[$]-MuR'         , 'Relative permeability (>1) of the material region', &
                                                                    numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('MagneticMaterial[$]-xyzMinMax'   , 'Bounding box (/xmin,xmax,ymin,ymax,zmin,zmax/) for region '//&
                                                                    'tagging', numberedmulti=.TRUE., no=6)
CALL prms%CreateLogicalOption(  'MagneticMaterial[$]-CheckRadius' , 'Additionally require |x-Center|<=Radius (spherical region)', &
                                                                    '.FALSE.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(     'MagneticMaterial[$]-Radius'      , 'Radius [m] for the optional spherical region test', &
                                                                    '-1.', numberedmulti=.TRUE.)
CALL prms%CreateRealArrayOption('MagneticMaterial[$]-Center'      , 'Center [m] for the optional radius test','0.,0.,0.', &
                                                                    numberedmulti=.TRUE., no=3)

END SUBROUTINE DefineParametersSuperB


SUBROUTINE InitializeSuperB()
!===================================================================================================================================
!> Read-in of SuperB parameters for permanent magnets, coils and time-dependent coils
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_SuperB_Vars
USE MOD_Globals_Vars       ,ONLY: PI
USE MOD_Interpolation_Vars ,ONLY: BGFieldVTKOutput
USE MOD_ReadInTools        ,ONLY: PrintOption
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: iMagnet, iCoil, iSegment, NbrOfTimeDepCoils
CHARACTER(LEN=32)  :: hilf,hilf2
REAL               :: FrequencyTmp
!===================================================================================================================================

! Get logical for calculating the error norms L2 and LInf of magnetic field
DoCalcErrorNormsSuperB = GETLOGICAL('DoCalcErrorNormsSuperB')

! Output of the magnets/coils as separate VTK files
BGFieldVTKOutput     = GETLOGICAL('PIC-CalcBField-OutputVTK')

! Get the number of magnets
NumOfPermanentMagnets= GETINT('NumOfPermanentMagnets')
! Allocate the magnets
ALLOCATE(PermanentMagnetInfo(NumOfPermanentMagnets))
! Read-in of magnet parameters
IF (NumOfPermanentMagnets.GT.0) THEN
  DO iMagnet = 1,NumOfPermanentMagnets
    SWRITE(*,*) "|       Read-in infos of permanent magnet |", iMagnet
    WRITE(UNIT=hilf,FMT='(I0)') iMagnet
    PermanentMagnetInfo(iMagnet)%Type               = GETSTR('PermanentMagnet'//TRIM(hilf)//'-Type')
    PermanentMagnetInfo(iMagnet)%BasePoint(1:3)     = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-BasePoint',3)
    PermanentMagnetInfo(iMagnet)%NumNodes           = GETINT('PermanentMagnet'//TRIM(hilf)//'-NumNodes')
    PermanentMagnetInfo(iMagnet)%Magnetisation(1:3) = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-Magnetisation',3)
    SELECT CASE(TRIM(PermanentMagnetInfo(iMagnet)%Type))
    CASE('cuboid')
      PermanentMagnetInfo(iMagnet)%BaseVector1(1:3)   = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-BaseVector1',3)
      PermanentMagnetInfo(iMagnet)%BaseVector2(1:3)   = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-BaseVector2',3)
      PermanentMagnetInfo(iMagnet)%BaseVector3(1:3)   = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-BaseVector3',3)
    CASE('sphere')
      PermanentMagnetInfo(iMagnet)%Radius             = GETREAL('PermanentMagnet'//TRIM(hilf)//'-Radius')
    CASE('cylinder')
      PermanentMagnetInfo(iMagnet)%Radius             = GETREAL('PermanentMagnet'//TRIM(hilf)//'-Radius')
      ! Default value for Radius2 is required because numberedmulti=.TRUE.
      ! For hollow cylinder (ring magnet) choose Radius2 < Radius
      PermanentMagnetInfo(iMagnet)%Radius2            = GETREAL('PermanentMagnet'//TRIM(hilf)//'-Radius2','0.')
      PermanentMagnetInfo(iMagnet)%HeightVector(1:3)  = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-HeightVector',3)

      IF(PermanentMagnetInfo(iMagnet)%Radius2.GT.0.0.AND.&
         PermanentMagnetInfo(iMagnet)%Radius2.GT.PermanentMagnetInfo(iMagnet)%Radius)THEN
         CALL abort(&
         __STAMP__&
         ,'Cylindrical magnet: Radius2 cannot be larger than Radius!')
      END IF ! PermanentMagnetInfo(iMagnet)%Radius2.GT.0.0.AND.
    CASE('conic')
      PermanentMagnetInfo(iMagnet)%Radius             = GETREAL('PermanentMagnet'//TRIM(hilf)//'-Radius')
      PermanentMagnetInfo(iMagnet)%Radius2            = GETREAL('PermanentMagnet'//TRIM(hilf)//'-Radius2')
      PermanentMagnetInfo(iMagnet)%HeightVector(1:3)  = GETREALARRAY('PermanentMagnet'//TRIM(hilf)//'-HeightVector',3)
    CASE DEFAULT
      CALL abort(__STAMP__, &
        'ERROR SuperB: Given permanent magnet geometry is not implemented! Permanent magnet number:', iMagnet)
    END SELECT

    ! Sanity Checks
    SELECT CASE(TRIM(PermanentMagnetInfo(iMagnet)%Type))
    CASE('sphere','cylinder','conic')
      IF(PermanentMagnetInfo(iMagnet)%Radius.LE.0.0)THEN
        CALL abort(&
        __STAMP__&
        ,'sphere/cylinder/conic magnet: Radius cannot be <= 0.0')
      END IF ! PermanentMagnetInfo(iMagnet)%Radius.LE.0.0
    END SELECT
  END DO
END IF

! Get the number of coils/conductors
NumOfCoils        = GETINT('NumOfCoils','0')
NbrOfTimeDepCoils = 0. ! Initialize
FrequencyTmp      = 0. ! Initialize
ALLOCATE(CoilInfo(NumOfCoils))
ALLOCATE(TimeDepCoil(NumOfCoils))
ALLOCATE(CurrentInfo(NumOfCoils))
! Read-in of coil/conductor parameters
IF (NumOfCoils.GT.0) THEN
  DO iCoil = 1,NumOfCoils
    !SWRITE(*,*) "|       Read-in infos of coil |", iCoil
    CALL PrintOption('Read-in infos of coil number','superB',IntOpt=iCoil)
    WRITE(UNIT=hilf,FMT='(I0)') iCoil
    CoilInfo(iCoil)%Type              = GETSTR('Coil'//TRIM(hilf)//'-Type')
    CoilInfo(iCoil)%BasePoint(1:3)    = GETREALARRAY('Coil'//TRIM(hilf)//'-BasePoint',3)
    CoilInfo(iCoil)%LengthVector(1:3) = GETREALARRAY('Coil'//TRIM(hilf)//'-LengthVector',3)
    CoilInfo(iCoil)%Length = SQRT(CoilInfo(iCoil)%LengthVector(1)**2 + CoilInfo(iCoil)%LengthVector(2)**2 + &
                                  CoilInfo(iCoil)%LengthVector(3)**2)
    ! --------------------- Coil type ---------------------------------------
    SELECT CASE(TRIM(CoilInfo(iCoil)%Type))
    CASE('custom')
      CoilInfo(iCoil)%AxisVec1 = GETREALARRAY('Coil'//TRIM(hilf)//'-AxisVec1',3)
      IF (DOT_PRODUCT(CoilInfo(iCoil)%LengthVector,CoilInfo(iCoil)%AxisVec1).NE.0) THEN
        CALL abort(__STAMP__, &
        'ERROR in pic_interpolation.f90: Length vector and axis vector of coil need to be orthogonal!')
      END IF
      CoilInfo(iCoil)%LoopNum = GETINT('Coil'//TRIM(hilf)//'-LoopNum')
      CoilInfo(iCoil)%NumOfSegments = GETINT('Coil'//TRIM(hilf)//'-NumOfSegments')
      ALLOCATE(CoilInfo(iCoil)%SegmentInfo(CoilInfo(iCoil)%NumOfSegments))
      ! Start with 1 Loop Point as zero
      CoilInfo(iCoil)%PointsPerLoop = 1
      DO iSegment = 1,CoilInfo(iCoil)%NumOfSegments
        WRITE(UNIT=hilf2,FMT='(I0)') iSegment
        CoilInfo(iCoil)%SegmentInfo(iSegment)%SegmentType = GETSTR('Coil'//TRIM(hilf)//'-Segment'//TRIM(hilf2)//'-SegmentType')
        CoilInfo(iCoil)%SegmentInfo(iSegment)%NumOfPoints = GETINT('Coil'//TRIM(hilf)//'-Segment'//TRIM(hilf2)//'-NumOfPoints')
        ! Add the number of segment points to the total loop points
        ! Attention: Add the start/endpoint of two adjacent segments only once
        CoilInfo(iCoil)%PointsPerLoop = CoilInfo(iCoil)%PointsPerLoop + (CoilInfo(iCoil)%SegmentInfo(iSegment)%NumOfPoints - 1)
        SELECT CASE(TRIM(CoilInfo(iCoil)%SegmentInfo(iSegment)%SegmentType))
        CASE('line')
          CoilInfo(iCoil)%SegmentInfo(iSegment)%LineVector = GETREALARRAY('Coil'//TRIM(hilf)//&
                                                              '-Segment'//TRIM(hilf2)//'-LineVector',2)
        CASE('circle')
          CoilInfo(iCoil)%SegmentInfo(iSegment)%Radius = GETREAL('Coil'//TRIM(hilf)//'-Segment'//TRIM(hilf2)//'-Radius')
          CoilInfo(iCoil)%SegmentInfo(iSegment)%Phi1   = GETREAL('Coil'//TRIM(hilf)//'-Segment'//TRIM(hilf2)//'-Phi1')*PI/180.
          CoilInfo(iCoil)%SegmentInfo(iSegment)%Phi2   = GETREAL('Coil'//TRIM(hilf)//'-Segment'//TRIM(hilf2)//'-Phi2')*PI/180.
        CASE DEFAULT
          CALL abort(__STAMP__, &
            'No valid segment type defined! Must be either 1 (Line) or 2 (Circle segment)!')
        END SELECT
      END DO
      ! Multiply the points per loop with the number of loops in the coil
      ! Attention: Add the start/endpoint of two adjacent loops only once and don't forget the starting point
      CoilInfo(iCoil)%NumNodes = (CoilInfo(iCoil)%PointsPerLoop - 1) * CoilInfo(iCoil)%LoopNum + 1
    CASE('circle')
      CoilInfo(iCoil)%Radius            = GETREAL('Coil'//TRIM(hilf)//'-Radius')
      CoilInfo(iCoil)%LoopNum           = GETINT('Coil'//TRIM(hilf)//'-LoopNum')
      CoilInfo(iCoil)%PointsPerLoop     = GETINT('Coil'//TRIM(hilf)//'-PointsPerLoop')
      CoilInfo(iCoil)%NumNodes          = CoilInfo(iCoil)%LoopNum * CoilInfo(iCoil)%PointsPerLoop + 1
    CASE('rectangle')
      CoilInfo(iCoil)%AxisVec1          = GETREALARRAY('Coil'//TRIM(hilf)//'-AxisVec1',3)
      IF (DOT_PRODUCT(CoilInfo(iCoil)%LengthVector,CoilInfo(iCoil)%AxisVec1).NE.0) THEN
        CALL abort(__STAMP__, &
        'ERROR in pic_interpolation.f90: Length vector and axis vector of coil need to be orthogonal!')
      END IF
      CoilInfo(iCoil)%RectVec1          = GETREALARRAY('Coil'//TRIM(hilf)//'-RectVec1',2)
      CoilInfo(iCoil)%RectVec2          = GETREALARRAY('Coil'//TRIM(hilf)//'-RectVec2',2)
      CoilInfo(iCoil)%LoopNum           = GETINT('Coil'//TRIM(hilf)//'-LoopNum')
      CoilInfo(iCoil)%PointsPerLoop     = GETINT('Coil'//TRIM(hilf)//'-PointsPerLoop')
      IF (MOD(CoilInfo(iCoil)%PointsPerLoop - 1,4).NE.0) THEN
        CoilInfo(iCoil)%PointsPerLoop   = CoilInfo(iCoil)%PointsPerLoop + 4 - MOD(CoilInfo(iCoil)%PointsPerLoop - 1,4)
      END IF
      ! Multiply the points per loop with the number of loops in the coil
      ! Attention: Only add the start/endpoint of two adjacent loops only once and don't forget the starting point
      CoilInfo(iCoil)%NumNodes = (CoilInfo(iCoil)%PointsPerLoop - 1) * CoilInfo(iCoil)%LoopNum + 1
    CASE('linear')
      CoilInfo(iCoil)%NumNodes = GETINT('Coil'//TRIM(hilf)//'-NumNodes')
    CASE DEFAULT
      CALL abort(__STAMP__, &
        'ERROR SuperB: Given coil geometry is not implemented! Coil number:', iCoil)
    END SELECT
    ! --------------------- Time-dependent current ---------------------------------------
    TimeDepCoil(iCoil) = GETLOGICAL('Coil'//TRIM(hilf)//'-TimeDepCoil')
    IF(TimeDepCoil(iCoil)) THEN
      NbrOfTimeDepCoils = NbrOfTimeDepCoils + 1
      CurrentInfo(iCoil)%CurrentFreq = GETREAL('Coil'//TRIM(hilf)//'-CurrentFrequency')
      CurrentInfo(iCoil)%CurrentPhase = GETREAL('Coil'//TRIM(hilf)//'-CurrentPhase')
      ! Check that all time-dependent coils use the same frequency
      IF((NbrOfTimeDepCoils.GT.1).AND.(.NOT.ALMOSTEQUALRELATIVE(CurrentInfo(iCoil)%CurrentFreq,FrequencyTmp,1e-5)))THEN
        CALL abort(__STAMP__,'All time-dependent coils must have the same frequency!')
      END IF
      FrequencyTmp = CurrentInfo(iCoil)%CurrentFreq
    END IF
    CoilInfo(iCoil)%Current = GETREAL('Coil'//TRIM(hilf)//'-Current')
  END DO
END IF

! Discretisation in time
UseTimeDepCoil=.FALSE.
IF (ANY(TimeDepCoil)) THEN
  UseTimeDepCoil = .TRUE.
  nTimePoints    = GETINT('nTimePoints')
  IF(nTimePoints.LT.2) CALL abort(__STAMP__,'nTimePoints cannot be smaller than 2')
END IF

! Soft-magnetic materials (mu_r>1): read regions and build the per-GP MuRField (no-op if NumOfMagneticMaterials=0)
CALL InitMagneticMaterials()

END SUBROUTINE InitializeSuperB


!==================================================================================================================================
!> Read soft-magnetic material regions (mu_r>1) and build the per-Gauss-point MuRField that seeds the HDG variable coefficient
!> (chitens = mu_r) for the reduced-scalar-potential (RSP) soft-iron correction (superB_main Step 5b, added separately).
!> All behaviour is guarded by NumOfMagneticMaterials>0; with 0 regions this returns immediately and superB output is
!> bit-identical to a build without this feature. Region tagging (bounding box + optional radius) clones the dielectric tagger.
!==================================================================================================================================
SUBROUTINE InitMagneticMaterials()
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_ReadInTools
USE MOD_SuperB_Vars
USE MOD_Mesh_Vars   ,ONLY: nElems, offSetElem, N_VolMesh
USE MOD_DG_Vars     ,ONLY: N_DG_Mapping
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iMat, iElem, Nloc, i, j, k
INTEGER           :: nTaggedGP, nTaggedElems, nTotalGP
LOGICAL           :: ElemTagged
REAL              :: xGP(3), rvec(3)
CHARACTER(LEN=32) :: hilf
#if USE_MPI
INTEGER           :: sendbuf(3), recvbuf(3)
#endif /*USE_MPI*/
!==================================================================================================================================
! May have been read already by the standalone superB driver (to decide on HDG bring-up); read once only.
IF(.NOT.MagMatParamsRead)THEN
  NumOfMagneticMaterials = GETINT('NumOfMagneticMaterials','0')
  UseMagneticMaterials   = (NumOfMagneticMaterials.GT.0)
  MagMatParamsRead       = .TRUE.
END IF
IF(.NOT.UseMagneticMaterials) RETURN
! Idempotency: the standalone HDG-RSP path builds MuRField before InitHDG; do not rebuild when called again from SuperB().
IF(MagneticMaterialsBuilt) RETURN

SWRITE(UNIT_stdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A,I0)') ' INIT SOFT-MAGNETIC MATERIALS (mu_r>1, RSP) - TOTAL NUMBER: ', NumOfMagneticMaterials

! --- Read region definitions
ALLOCATE(MagneticMaterialInfo(NumOfMagneticMaterials))
DO iMat = 1, NumOfMagneticMaterials
  WRITE(UNIT=hilf,FMT='(I0)') iMat
  MagneticMaterialInfo(iMat)%MuR         = GETREAL(     'MagneticMaterial'//TRIM(hilf)//'-MuR')
  MagneticMaterialInfo(iMat)%xyzMinMax   = GETREALARRAY('MagneticMaterial'//TRIM(hilf)//'-xyzMinMax',6)
  MagneticMaterialInfo(iMat)%CheckRadius = GETLOGICAL(  'MagneticMaterial'//TRIM(hilf)//'-CheckRadius')
  MagneticMaterialInfo(iMat)%Radius      = GETREAL(     'MagneticMaterial'//TRIM(hilf)//'-Radius')
  MagneticMaterialInfo(iMat)%Center      = GETREALARRAY('MagneticMaterial'//TRIM(hilf)//'-Center',3)
  IF(MagneticMaterialInfo(iMat)%MuR.LE.0.0) &
    CALL abort(__STAMP__,'MagneticMaterial MuR must be > 0. Region:',iMat)
  IF(MagneticMaterialInfo(iMat)%CheckRadius.AND.(MagneticMaterialInfo(iMat)%Radius.LE.0.0)) &
    CALL abort(__STAMP__,'MagneticMaterial CheckRadius=T requires Radius>0. Region:',iMat)
END DO ! iMat

! --- Build the per-Gauss-point MuRField (1.0 = vacuum/air; mu_r inside a tagged region; first matching region wins)
ALLOCATE(MagneticMaterial(1:nElems))
nTaggedGP = 0; nTaggedElems = 0; nTotalGP = 0
DO iElem = 1, nElems
  Nloc = N_DG_Mapping(2,iElem+offSetElem)
  ALLOCATE(MagneticMaterial(iElem)%MuRField(0:Nloc,0:Nloc,0:Nloc))
  ALLOCATE(MagneticMaterial(iElem)%MatTag(  0:Nloc,0:Nloc,0:Nloc))
  MagneticMaterial(iElem)%MuRField = 1.0
  MagneticMaterial(iElem)%MatTag   = 0
  ElemTagged = .FALSE.
  DO k=0,Nloc; DO j=0,Nloc; DO i=0,Nloc
    nTotalGP = nTotalGP + 1
    xGP = N_VolMesh(iElem)%Elem_xGP(1:3,i,j,k)
    DO iMat = 1, NumOfMagneticMaterials
      ASSOCIATE( bb => MagneticMaterialInfo(iMat)%xyzMinMax )
        IF((xGP(1).LT.bb(1)).OR.(xGP(1).GT.bb(2))) CYCLE
        IF((xGP(2).LT.bb(3)).OR.(xGP(2).GT.bb(4))) CYCLE
        IF((xGP(3).LT.bb(5)).OR.(xGP(3).GT.bb(6))) CYCLE
      END ASSOCIATE
      IF(MagneticMaterialInfo(iMat)%CheckRadius)THEN
        rvec = xGP - MagneticMaterialInfo(iMat)%Center
        IF(SQRT(SUM(rvec**2)).GT.MagneticMaterialInfo(iMat)%Radius) CYCLE
      END IF
      ! Gauss point lies inside region iMat
      MagneticMaterial(iElem)%MuRField(i,j,k) = MagneticMaterialInfo(iMat)%MuR
      MagneticMaterial(iElem)%MatTag(i,j,k)   = iMat
      nTaggedGP  = nTaggedGP + 1
      ElemTagged = .TRUE.
      EXIT ! first matching region wins
    END DO ! iMat
  END DO; END DO; END DO ! i,j,k
  IF(ElemTagged) nTaggedElems = nTaggedElems + 1
END DO ! iElem
MagneticMaterialsBuilt = .TRUE.

#if USE_MPI
! NB: explicit send buffer, NOT MPI_IN_PLACE (MS-MPI zeros the buffer for in-place reduce on this build)
sendbuf = (/nTaggedGP, nTaggedElems, nTotalGP/)
CALL MPI_REDUCE(sendbuf, recvbuf, 3, MPI_INTEGER, MPI_SUM, 0, MPI_COMM_PICLAS, iError)
IF(MPIRoot)THEN; nTaggedGP=recvbuf(1); nTaggedElems=recvbuf(2); nTotalGP=recvbuf(3); END IF
#endif /*USE_MPI*/
SWRITE(UNIT_stdOut,'(A,I0,A,I0,A,F6.2,A)') ' | Tagged ',nTaggedElems,' elements, ',nTaggedGP, &
    ' Gauss points as soft-magnetic material (',100.*REAL(nTaggedGP)/REAL(MAX(nTotalGP,1)),' % of domain GP).'
SWRITE(UNIT_stdOut,'(A)') ' INIT SOFT-MAGNETIC MATERIALS DONE!'
SWRITE(UNIT_stdOut,'(132("-"))')

END SUBROUTINE InitMagneticMaterials


#if USE_HDG
!==================================================================================================================================
!> Overwrite the HDG variable coefficient chitens with the soft-magnetic relative permeability mu_r (isotropic: diagonal = MuRField,
!> inverse = 1/MuRField). Must be called AFTER InitChiTens (allocates chi=identity) and BEFORE InitHDG (which bakes chi into the
!> element matrices). This makes the HDG operator solve div(mu_r grad Psi), the LHS of the reduced-scalar-potential soft-iron problem.
!==================================================================================================================================
SUBROUTINE SetChiTensFromMuR()
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_SuperB_Vars   ,ONLY: UseMagneticMaterials, MagneticMaterial
USE MOD_Equation_Vars ,ONLY: chi
USE MOD_Mesh_Vars     ,ONLY: offSetElem
USE MOD_DG_Vars       ,ONLY: N_DG_Mapping
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
INTEGER :: iElem, Nloc, i, j, k
REAL    :: mur
!==================================================================================================================================
IF(.NOT.UseMagneticMaterials) RETURN
DO iElem = 1, PP_nElems
  Nloc = N_DG_Mapping(2,iElem+offSetElem)
  DO k=0,Nloc; DO j=0,Nloc; DO i=0,Nloc
    mur = MagneticMaterial(iElem)%MuRField(i,j,k)
    chi(iElem)%tens(:,:,i,j,k)    = 0.
    chi(iElem)%tens(1,1,i,j,k)    = mur
    chi(iElem)%tens(2,2,i,j,k)    = mur
    chi(iElem)%tens(3,3,i,j,k)    = mur
    chi(iElem)%tensInv(:,:,i,j,k) = 0.
    chi(iElem)%tensInv(1,1,i,j,k) = 1./mur
    chi(iElem)%tensInv(2,2,i,j,k) = 1./mur
    chi(iElem)%tensInv(3,3,i,j,k) = 1./mur
  END DO; END DO; END DO
END DO ! iElem
SWRITE(UNIT_stdOut,'(A)') ' | Soft-iron: HDG chitens set to mu_r (variable-coefficient RSP operator).'
END SUBROUTINE SetChiTensFromMuR
#endif /*USE_HDG*/


SUBROUTINE FinalizeSuperB()
!----------------------------------------------------------------------------------------------------------------------------------!
! Deallocate the respective arrays used by superB
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_SuperB_Vars
USE MOD_Mesh_Vars     ,ONLY: nElems
USE MOD_Interpolation_Vars, ONLY: N_BG
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER         :: iElem
!===================================================================================================================================
SDEALLOCATE(TimeDepCoil)
IF(ALLOCATED(N_BG))THEN
  DO iElem = 1, nElems
    SDEALLOCATE(N_BG(iElem)%BGFieldTDep)
  END DO
END IF ! ALLOCATED(N_BG)
! Soft-magnetic materials
IF(ALLOCATED(MagneticMaterial))THEN
  DO iElem = 1, nElems
    SDEALLOCATE(MagneticMaterial(iElem)%MuRField)
    SDEALLOCATE(MagneticMaterial(iElem)%MatTag)
  END DO
  DEALLOCATE(MagneticMaterial)
END IF ! ALLOCATED(MagneticMaterial)
SDEALLOCATE(MagneticMaterialInfo)
END SUBROUTINE FinalizeSuperB

END MODULE MOD_SuperB_Init
