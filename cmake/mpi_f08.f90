!=============================================================================
! mpi_f08 compatibility module for MS-MPI (Windows / MSYS2 UCRT64)
!
! MS-MPI provides only the legacy Fortran 90 interface (MODULE MPI).
! This module provides the Fortran 2008 derived-handle types and typed
! procedure wrappers on top of that interface so PICLas can compile with
! "USE mpi_f08" on Windows.
!
! NOTE: All legacy MPI procedures are imported at module level (not inside
! subprograms) to avoid a gfortran 15 internal compiler error (ICE/segfault
! in f951.exe) that is triggered by combining "USE mpi" with
! TYPE(*)/NO_ARG_CHECK inside MODULE subprograms.
!
! Generated for PICLas Windows port – gfortran 15 / MSYS2 UCRT64 / MS-MPI v10
!=============================================================================
MODULE mpi_f08
  ! Import ALL legacy procedures under f90_* names to avoid name collisions
  ! with our typed wrappers defined in CONTAINS.
  USE mpi, ONLY: &
    f90_comm_rank            => MPI_COMM_RANK,           &
    f90_comm_size            => MPI_COMM_SIZE,           &
    f90_comm_dup             => MPI_COMM_DUP,            &
    f90_comm_free            => MPI_COMM_FREE,           &
    f90_comm_split           => MPI_COMM_SPLIT,          &
    f90_comm_split_type      => MPI_COMM_SPLIT_TYPE,     &
    f90_comm_create          => MPI_COMM_CREATE,         &
    f90_comm_compare         => MPI_COMM_COMPARE,        &
    f90_comm_group           => MPI_COMM_GROUP,          &
    f90_group_free           => MPI_GROUP_FREE,          &
    f90_group_size           => MPI_GROUP_SIZE,          &
    f90_group_rank           => MPI_GROUP_RANK,          &
    f90_comm_set_errhandler  => MPI_COMM_SET_ERRHANDLER, &
    f90_barrier              => MPI_BARRIER,             &
    f90_bcast                => MPI_Bcast,               &
    f90_reduce               => MPI_Reduce,              &
    f90_allreduce            => MPI_Allreduce,           &
    f90_gather               => MPI_Gather,              &
    f90_gatherv              => MPI_Gatherv,             &
    f90_allgather            => MPI_Allgather,           &
    f90_allgatherv           => MPI_Allgatherv,          &
    f90_scatter              => MPI_Scatter,             &
    f90_scatterv             => MPI_Scatterv,            &
    f90_scan                 => MPI_Scan,                &
    f90_exscan               => MPI_Exscan,              &
    f90_send                 => MPI_Send,                &
    f90_recv                 => MPI_Recv,                &
    f90_isend                => MPI_Isend,               &
    f90_irecv                => MPI_Irecv,               &
    f90_wait                 => MPI_WAIT,                &
    f90_waitall              => MPI_WAITALL,             &
    f90_test                 => MPI_TEST,                &
    f90_sendrecv             => MPI_Sendrecv,            &
    f90_type_create_struct   => MPI_TYPE_CREATE_STRUCT,  &
    f90_type_commit          => MPI_TYPE_COMMIT,         &
    f90_type_free            => MPI_TYPE_FREE,           &
    f90_type_size            => MPI_TYPE_SIZE,           &
    f90_type_get_extent      => MPI_TYPE_GET_EXTENT,     &
    f90_type_contiguous      => MPI_TYPE_CONTIGUOUS,     &
    f90_type_vector          => MPI_TYPE_VECTOR,         &
    f90_type_create_subarray => MPI_TYPE_CREATE_SUBARRAY,&
    f90_type_create_resized  => MPI_TYPE_CREATE_RESIZED, &
    f90_info_create          => MPI_INFO_CREATE,         &
    f90_info_free            => MPI_INFO_FREE,           &
    f90_info_set             => MPI_INFO_SET,            &
    f90_info_get             => MPI_INFO_GET,            &
    f90_info_dup             => MPI_INFO_DUP,            &
    f90_win_free             => MPI_WIN_FREE,            &
    f90_win_sync             => MPI_Win_sync,            &
    f90_win_lock_all         => MPI_Win_lock_all,        &
    f90_win_unlock_all       => MPI_Win_unlock_all,      &
    f90_win_flush_all        => MPI_Win_flush_all,       &
    f90_win_fence            => MPI_WIN_FENCE,           &
    f90_win_create           => MPI_Win_create,          &
    f90_win_allocate_shared  => MPI_Win_allocate_shared, &
    f90_win_shared_query     => MPI_Win_shared_query,    &
    f90_abort                => MPI_ABORT,               &
    f90_get_address          => MPI_Get_address,         &
    f90_error_string         => MPI_ERROR_STRING,        &
    f90_get_count            => MPI_GET_COUNT,           &
    f90_op_create            => MPI_OP_CREATE,           &
    f90_op_free              => MPI_OP_FREE,             &
    f90_wtime                => MPI_WTIME,               &
    f90_wtick                => MPI_WTICK
  IMPLICIT NONE

  !---------------------------------------------------------------------------
  ! Opaque handle types (one INTEGER component each – same memory layout)
  !---------------------------------------------------------------------------
  TYPE :: MPI_Comm
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Comm

  TYPE :: MPI_Win
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Win

  TYPE :: MPI_Request
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Request

  TYPE :: MPI_Info
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Info

  TYPE :: MPI_Datatype
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Datatype

  TYPE :: MPI_Op
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Op

  TYPE :: MPI_Group
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Group

  TYPE :: MPI_Errhandler
    INTEGER :: MPI_VAL = 0
  END TYPE MPI_Errhandler

  ! MPI_Status: 5 integers matching MS-MPI MPI_STATUS_SIZE=5
  ! indices: SOURCE=3, TAG=4, ERROR=5 (1-based Fortran)
  TYPE :: MPI_Status
    INTEGER :: MPI_SOURCE = 0
    INTEGER :: MPI_TAG    = 0
    INTEGER :: MPI_ERROR  = 0
    INTEGER :: INTERNAL(2) = 0
  END TYPE MPI_Status

  !---------------------------------------------------------------------------
  ! Kind parameters
  !---------------------------------------------------------------------------
  INTEGER, PARAMETER :: MPI_ADDRESS_KIND = 8
  INTEGER, PARAMETER :: MPI_STATUS_SIZE  = 5

  !---------------------------------------------------------------------------
  ! Communicator handle constants (MS-MPI integer values wrapped in TYPE)
  !---------------------------------------------------------------------------
  TYPE(MPI_Comm),    PARAMETER :: MPI_COMM_WORLD  = MPI_Comm(1140850688)
  TYPE(MPI_Comm),    PARAMETER :: MPI_COMM_SELF   = MPI_Comm(1140850692)
  TYPE(MPI_Comm),    PARAMETER :: MPI_COMM_NULL   = MPI_Comm(67108864)
  TYPE(MPI_Win),     PARAMETER :: MPI_WIN_NULL    = MPI_Win(536870912)
  TYPE(MPI_Request), PARAMETER :: MPI_REQUEST_NULL= MPI_Request(738197504)
  TYPE(MPI_Info),    PARAMETER :: MPI_INFO_NULL   = MPI_Info(469762048)
  TYPE(MPI_Group),   PARAMETER :: MPI_GROUP_NULL  = MPI_Group(335544320)
  TYPE(MPI_Group),   PARAMETER :: MPI_GROUP_EMPTY = MPI_Group(335544321)

  !---------------------------------------------------------------------------
  ! Datatype constants
  !---------------------------------------------------------------------------
  ! All constants taken directly from the MS-MPI SDK mpi.f90 (mpi.f90 PARAMETER values).
  TYPE(MPI_Datatype), PARAMETER :: MPI_DATATYPE_NULL    = MPI_Datatype(0)
  TYPE(MPI_Datatype), PARAMETER :: MPI_BYTE             = MPI_Datatype(1275068685)
  TYPE(MPI_Datatype), PARAMETER :: MPI_PACKED           = MPI_Datatype(1275068687)
  TYPE(MPI_Datatype), PARAMETER :: MPI_CHARACTER        = MPI_Datatype(1275068698)
  TYPE(MPI_Datatype), PARAMETER :: MPI_LOGICAL          = MPI_Datatype(1275069469)
  TYPE(MPI_Datatype), PARAMETER :: MPI_INTEGER          = MPI_Datatype(1275069467)
  TYPE(MPI_Datatype), PARAMETER :: MPI_INTEGER1         = MPI_Datatype(1275068717)
  TYPE(MPI_Datatype), PARAMETER :: MPI_INTEGER2         = MPI_Datatype(1275068975)
  TYPE(MPI_Datatype), PARAMETER :: MPI_INTEGER4         = MPI_Datatype(1275069488)
  TYPE(MPI_Datatype), PARAMETER :: MPI_INTEGER8         = MPI_Datatype(1275070513)
  TYPE(MPI_Datatype), PARAMETER :: MPI_REAL             = MPI_Datatype(1275069468)
  TYPE(MPI_Datatype), PARAMETER :: MPI_REAL4            = MPI_Datatype(1275069479)
  TYPE(MPI_Datatype), PARAMETER :: MPI_REAL8            = MPI_Datatype(1275070505)
  TYPE(MPI_Datatype), PARAMETER :: MPI_DOUBLE_PRECISION = MPI_Datatype(1275070495)
  TYPE(MPI_Datatype), PARAMETER :: MPI_COMPLEX          = MPI_Datatype(1275070494)
  TYPE(MPI_Datatype), PARAMETER :: MPI_DOUBLE_COMPLEX   = MPI_Datatype(1275072546)
  TYPE(MPI_Datatype), PARAMETER :: MPI_2INTEGER         = MPI_Datatype(1275070496)
  TYPE(MPI_Datatype), PARAMETER :: MPI_2REAL            = MPI_Datatype(1275070497)
  TYPE(MPI_Datatype), PARAMETER :: MPI_2DOUBLE_PRECISION= MPI_Datatype(1275072547)
  TYPE(MPI_Datatype), PARAMETER :: MPI_UB               = MPI_Datatype(1275068433)
  TYPE(MPI_Datatype), PARAMETER :: MPI_LB               = MPI_Datatype(1275068432)

  !---------------------------------------------------------------------------
  ! Reduction operator constants
  !---------------------------------------------------------------------------
  TYPE(MPI_Op), PARAMETER :: MPI_OP_NULL = MPI_Op(0)
  TYPE(MPI_Op), PARAMETER :: MPI_MAX     = MPI_Op(1476395009)
  TYPE(MPI_Op), PARAMETER :: MPI_MIN     = MPI_Op(1476395010)
  TYPE(MPI_Op), PARAMETER :: MPI_SUM     = MPI_Op(1476395011)
  TYPE(MPI_Op), PARAMETER :: MPI_PROD    = MPI_Op(1476395012)
  TYPE(MPI_Op), PARAMETER :: MPI_LAND    = MPI_Op(1476395013)
  TYPE(MPI_Op), PARAMETER :: MPI_BAND    = MPI_Op(1476395014)
  TYPE(MPI_Op), PARAMETER :: MPI_LOR     = MPI_Op(1476395015)
  TYPE(MPI_Op), PARAMETER :: MPI_BOR     = MPI_Op(1476395016)
  TYPE(MPI_Op), PARAMETER :: MPI_LXOR    = MPI_Op(1476395017)
  TYPE(MPI_Op), PARAMETER :: MPI_BXOR    = MPI_Op(1476395018)
  TYPE(MPI_Op), PARAMETER :: MPI_MINLOC  = MPI_Op(1476395019)
  TYPE(MPI_Op), PARAMETER :: MPI_MAXLOC  = MPI_Op(1476395020)
  TYPE(MPI_Op), PARAMETER :: MPI_REPLACE = MPI_Op(1476395021)
  TYPE(MPI_Op), PARAMETER :: MPI_NO_OP   = MPI_Op(1476395022)

  !---------------------------------------------------------------------------
  ! Integer constants
  !---------------------------------------------------------------------------
  INTEGER, PARAMETER :: MPI_SUCCESS          = 0
  INTEGER, PARAMETER :: MPI_ANY_SOURCE       = -2
  INTEGER, PARAMETER :: MPI_ANY_TAG          = -1
  INTEGER, PARAMETER :: MPI_PROC_NULL        = -3
  INTEGER, PARAMETER :: MPI_UNDEFINED        = -32766
  INTEGER, PARAMETER :: MPI_KEYVAL_INVALID   = -1
  INTEGER, PARAMETER :: MPI_THREAD_SINGLE    = 0
  INTEGER, PARAMETER :: MPI_THREAD_FUNNELED  = 1
  INTEGER, PARAMETER :: MPI_THREAD_SERIALIZED= 2
  INTEGER, PARAMETER :: MPI_THREAD_MULTIPLE  = 3
  INTEGER, PARAMETER :: MPI_COMM_TYPE_SHARED = 1
  INTEGER, PARAMETER :: MPI_IDENT            = 0
  INTEGER, PARAMETER :: MPI_CONGRUENT        = 1
  INTEGER, PARAMETER :: MPI_SIMILAR          = 2
  INTEGER, PARAMETER :: MPI_UNEQUAL          = 3
  INTEGER, PARAMETER :: MPI_MAX_ERROR_STRING = 511
  INTEGER, PARAMETER :: MPI_MAX_PROCESSOR_NAME = 127
  INTEGER, PARAMETER :: MPI_ORDER_C          = 56
  INTEGER, PARAMETER :: MPI_ORDER_FORTRAN    = 57

  !---------------------------------------------------------------------------
  ! DLLIMPORT COMMON block variables: MPI_BOTTOM, MPI_IN_PLACE,
  ! MPI_STATUS_IGNORE (integer array), MPI_STATUSES_IGNORE
  ! These must match the COMMON blocks in MS-MPI exactly.
  !---------------------------------------------------------------------------
  INTEGER :: MPI_BOTTOM
  INTEGER :: MPI_IN_PLACE
  INTEGER :: MPI_STATUS_IGNORE_INT(MPI_STATUS_SIZE)
  INTEGER :: MPI_STATUSES_IGNORE_INT(MPI_STATUS_SIZE, 1)
  INTEGER :: MPI_ERRCODES_IGNORE(1)
  COMMON /MPIPRIV1/ MPI_BOTTOM, MPI_IN_PLACE, MPI_STATUS_IGNORE_INT
  COMMON /MPIPRIV2/ MPI_STATUSES_IGNORE_INT, MPI_ERRCODES_IGNORE
  ! Note: gfortran links COMMON blocks in DLLs automatically via the import lib

  ! Typed alias for MPI_STATUS_IGNORE usable in mpi_f08 contexts.
  ! Our wrappers never forward this to the C layer; they use a local
  ! integer status array instead.
  TYPE(MPI_Status) :: MPI_STATUS_IGNORE
  TYPE(MPI_Status) :: MPI_STATUSES_IGNORE(1)

  !---------------------------------------------------------------------------
  ! Comparison operators for handle types (required by mpi_f08 standard)
  ! MPI 3.1 section 17.1.1: handles support == and /= comparisons
  !---------------------------------------------------------------------------
  INTERFACE OPERATOR(==)
    MODULE PROCEDURE MPI_Comm_eq, MPI_Win_eq, MPI_Request_eq, MPI_Info_eq, &
                     MPI_Datatype_eq, MPI_Op_eq, MPI_Group_eq, MPI_Errhandler_eq
  END INTERFACE OPERATOR(==)

  INTERFACE OPERATOR(/=)
    MODULE PROCEDURE MPI_Comm_neq, MPI_Win_neq, MPI_Request_neq, MPI_Info_neq, &
                     MPI_Datatype_neq, MPI_Op_neq, MPI_Group_neq, MPI_Errhandler_neq
  END INTERFACE OPERATOR(/=)

CONTAINS

  !==========================================================================
  ! Communicator operations
  !==========================================================================

  SUBROUTINE MPI_COMM_RANK(comm, rank, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    INTEGER,        INTENT(OUT) :: rank
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_comm_rank(comm%MPI_VAL, rank, ierror)
  END SUBROUTINE MPI_COMM_RANK

  SUBROUTINE MPI_COMM_SIZE(comm, size, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    INTEGER,        INTENT(OUT) :: size, ierror
    CALL f90_comm_size(comm%MPI_VAL, size, ierror)
  END SUBROUTINE MPI_COMM_SIZE

  SUBROUTINE MPI_COMM_DUP(comm, newcomm, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    TYPE(MPI_Comm), INTENT(OUT) :: newcomm
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_comm_dup(comm%MPI_VAL, newcomm%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_DUP

  SUBROUTINE MPI_COMM_FREE(comm, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(INOUT) :: comm
    INTEGER,        INTENT(OUT)   :: ierror
    CALL f90_comm_free(comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_FREE

  SUBROUTINE MPI_COMM_SPLIT(comm, color, key, newcomm, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    INTEGER,        INTENT(IN)  :: color, key
    TYPE(MPI_Comm), INTENT(OUT) :: newcomm
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_comm_split(comm%MPI_VAL, color, key, newcomm%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_SPLIT

  SUBROUTINE MPI_COMM_SPLIT_TYPE(comm, split_type, key, info, newcomm, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    INTEGER,        INTENT(IN)  :: split_type, key
    TYPE(MPI_Info), INTENT(IN)  :: info
    TYPE(MPI_Comm), INTENT(OUT) :: newcomm
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_comm_split_type(comm%MPI_VAL, split_type, key, info%MPI_VAL, &
                             newcomm%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_SPLIT_TYPE

  SUBROUTINE MPI_COMM_CREATE(comm, group, newcomm, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm),  INTENT(IN)  :: comm
    TYPE(MPI_Group), INTENT(IN)  :: group
    TYPE(MPI_Comm),  INTENT(OUT) :: newcomm
    INTEGER,         INTENT(OUT) :: ierror
    CALL f90_comm_create(comm%MPI_VAL, group%MPI_VAL, newcomm%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_CREATE

  SUBROUTINE MPI_COMM_COMPARE(comm1, comm2, result, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm1, comm2
    INTEGER,        INTENT(OUT) :: result, ierror
    CALL f90_comm_compare(comm1%MPI_VAL, comm2%MPI_VAL, result, ierror)
  END SUBROUTINE MPI_COMM_COMPARE

  SUBROUTINE MPI_COMM_GROUP(comm, group, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm),  INTENT(IN)  :: comm
    TYPE(MPI_Group), INTENT(OUT) :: group
    INTEGER,         INTENT(OUT) :: ierror
    CALL f90_comm_group(comm%MPI_VAL, group%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_GROUP

  SUBROUTINE MPI_GROUP_FREE(group, ierror)
    IMPLICIT NONE
    TYPE(MPI_Group), INTENT(INOUT) :: group
    INTEGER,         INTENT(OUT)   :: ierror
    CALL f90_group_free(group%MPI_VAL, ierror)
  END SUBROUTINE MPI_GROUP_FREE

  SUBROUTINE MPI_GROUP_SIZE(group, size, ierror)
    IMPLICIT NONE
    TYPE(MPI_Group), INTENT(IN)  :: group
    INTEGER,         INTENT(OUT) :: size, ierror
    CALL f90_group_size(group%MPI_VAL, size, ierror)
  END SUBROUTINE MPI_GROUP_SIZE

  SUBROUTINE MPI_GROUP_RANK(group, rank, ierror)
    IMPLICIT NONE
    TYPE(MPI_Group), INTENT(IN)  :: group
    INTEGER,         INTENT(OUT) :: rank, ierror
    CALL f90_group_rank(group%MPI_VAL, rank, ierror)
  END SUBROUTINE MPI_GROUP_RANK

  SUBROUTINE MPI_COMM_SET_ERRHANDLER(comm, errhandler, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm),       INTENT(IN)  :: comm
    TYPE(MPI_Errhandler), INTENT(IN)  :: errhandler
    INTEGER,              INTENT(OUT) :: ierror
    CALL f90_comm_set_errhandler(comm%MPI_VAL, errhandler%MPI_VAL, ierror)
  END SUBROUTINE MPI_COMM_SET_ERRHANDLER

  !==========================================================================
  ! Collective operations
  !==========================================================================

  SUBROUTINE MPI_BARRIER(comm, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_barrier(comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_BARRIER

  SUBROUTINE MPI_BCAST(buffer, count, datatype, root, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: buffer
    TYPE(*), DIMENSION(*) :: buffer
    INTEGER,               INTENT(IN)   :: count, root
    TYPE(MPI_Datatype),    INTENT(IN)   :: datatype
    TYPE(MPI_Comm),        INTENT(IN)   :: comm
    INTEGER,               INTENT(OUT)  :: ierror
    CALL f90_bcast(buffer, count, datatype%MPI_VAL, root, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_BCAST

  SUBROUTINE MPI_REDUCE(sendbuf, recvbuf, count, datatype, op, root, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)   :: sendbuf
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)               :: recvbuf
    INTEGER,               INTENT(IN)   :: count, root
    TYPE(MPI_Datatype),    INTENT(IN)   :: datatype
    TYPE(MPI_Op),          INTENT(IN)   :: op
    TYPE(MPI_Comm),        INTENT(IN)   :: comm
    INTEGER,               INTENT(OUT)  :: ierror
    CALL f90_reduce(sendbuf, recvbuf, count, datatype%MPI_VAL, op%MPI_VAL, &
                    root, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_REDUCE

  SUBROUTINE MPI_ALLREDUCE(sendbuf, recvbuf, count, datatype, op, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: count
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Op),          INTENT(IN)    :: op
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_allreduce(sendbuf, recvbuf, count, datatype%MPI_VAL, op%MPI_VAL, &
                       comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_ALLREDUCE

  SUBROUTINE MPI_GATHER(sendbuf, sendcount, sendtype, recvbuf, recvcount, &
                        recvtype, root, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    INTEGER,               INTENT(IN)    :: root
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_gather(sendbuf, sendcount, sendtype%MPI_VAL, recvbuf, recvcount, &
                    recvtype%MPI_VAL, root, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_GATHER

  SUBROUTINE MPI_GATHERV(sendbuf, sendcount, sendtype, recvbuf, recvcounts, &
                         displs, recvtype, root, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcounts(*), displs(*)
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    INTEGER,               INTENT(IN)    :: root
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_gatherv(sendbuf, sendcount, sendtype%MPI_VAL, recvbuf, recvcounts, &
                     displs, recvtype%MPI_VAL, root, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_GATHERV

  SUBROUTINE MPI_ALLGATHER(sendbuf, sendcount, sendtype, recvbuf, recvcount, &
                           recvtype, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_allgather(sendbuf, sendcount, sendtype%MPI_VAL, recvbuf, recvcount, &
                       recvtype%MPI_VAL, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_ALLGATHER

  SUBROUTINE MPI_ALLGATHERV(sendbuf, sendcount, sendtype, recvbuf, recvcounts, &
                            displs, recvtype, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcounts(*), displs(*)
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_allgatherv(sendbuf, sendcount, sendtype%MPI_VAL, recvbuf, recvcounts, &
                        displs, recvtype%MPI_VAL, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_ALLGATHERV

  SUBROUTINE MPI_SCATTER(sendbuf, sendcount, sendtype, recvbuf, recvcount, &
                         recvtype, root, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    INTEGER,               INTENT(IN)    :: root
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_scatter(sendbuf, sendcount, sendtype%MPI_VAL, recvbuf, recvcount, &
                     recvtype%MPI_VAL, root, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_SCATTER

  SUBROUTINE MPI_SCATTERV(sendbuf, sendcounts, displs, sendtype, recvbuf, &
                          recvcount, recvtype, root, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcounts(*), displs(*)
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcount
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    INTEGER,               INTENT(IN)    :: root
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_scatterv(sendbuf, sendcounts, displs, sendtype%MPI_VAL, recvbuf, &
                      recvcount, recvtype%MPI_VAL, root, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_SCATTERV

  SUBROUTINE MPI_SCAN(sendbuf, recvbuf, count, datatype, op, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: count
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Op),          INTENT(IN)    :: op
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_scan(sendbuf, recvbuf, count, datatype%MPI_VAL, op%MPI_VAL, &
                  comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_SCAN

  SUBROUTINE MPI_EXSCAN(sendbuf, recvbuf, count, datatype, op, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: count
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Op),          INTENT(IN)    :: op
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_exscan(sendbuf, recvbuf, count, datatype%MPI_VAL, op%MPI_VAL, &
                    comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_EXSCAN

  !==========================================================================
  ! Point-to-point
  !==========================================================================

  SUBROUTINE MPI_SEND(buf, count, datatype, dest, tag, comm, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: buf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: buf
    INTEGER,               INTENT(IN)    :: count, dest, tag
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_send(buf, count, datatype%MPI_VAL, dest, tag, comm%MPI_VAL, ierror)
  END SUBROUTINE MPI_SEND

  SUBROUTINE MPI_RECV(buf, count, datatype, source, tag, comm, status, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: buf
    TYPE(*), DIMENSION(*)                :: buf
    INTEGER,               INTENT(IN)    :: count, source, tag
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    TYPE(MPI_Status),      INTENT(OUT)   :: status
    INTEGER,               INTENT(OUT)   :: ierror
    INTEGER :: ist(MPI_STATUS_SIZE)
    CALL f90_recv(buf, count, datatype%MPI_VAL, source, tag, comm%MPI_VAL, &
                  ist, ierror)
    status%MPI_SOURCE = ist(3)
    status%MPI_TAG    = ist(4)
    status%MPI_ERROR  = ist(5)
  END SUBROUTINE MPI_RECV

  SUBROUTINE MPI_ISEND(buf, count, datatype, dest, tag, comm, request, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: buf
    TYPE(*), DIMENSION(*), ASYNCHRONOUS  :: buf
    INTEGER,               INTENT(IN)    :: count, dest, tag
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    TYPE(MPI_Request),     INTENT(OUT)   :: request
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_isend(buf, count, datatype%MPI_VAL, dest, tag, comm%MPI_VAL, &
                   request%MPI_VAL, ierror)
  END SUBROUTINE MPI_ISEND

  SUBROUTINE MPI_IRECV(buf, count, datatype, source, tag, comm, request, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: buf
    TYPE(*), DIMENSION(*), ASYNCHRONOUS  :: buf
    INTEGER,               INTENT(IN)    :: count, source, tag
    TYPE(MPI_Datatype),    INTENT(IN)    :: datatype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    TYPE(MPI_Request),     INTENT(OUT)   :: request
    INTEGER,               INTENT(OUT)   :: ierror
    CALL f90_irecv(buf, count, datatype%MPI_VAL, source, tag, comm%MPI_VAL, &
                   request%MPI_VAL, ierror)
  END SUBROUTINE MPI_IRECV

  SUBROUTINE MPI_WAIT(request, status, ierror)
    IMPLICIT NONE
    TYPE(MPI_Request), INTENT(INOUT) :: request
    TYPE(MPI_Status),  INTENT(OUT)   :: status
    INTEGER,           INTENT(OUT)   :: ierror
    INTEGER :: ist(MPI_STATUS_SIZE)
    CALL f90_wait(request%MPI_VAL, ist, ierror)
    request%MPI_VAL   = MPI_REQUEST_NULL%MPI_VAL
    status%MPI_SOURCE = ist(3)
    status%MPI_TAG    = ist(4)
    status%MPI_ERROR  = ist(5)
  END SUBROUTINE MPI_WAIT

  SUBROUTINE MPI_WAITALL(count, array_of_requests, array_of_statuses, ierror)
    IMPLICIT NONE
    INTEGER,           INTENT(IN)    :: count
    TYPE(MPI_Request), INTENT(INOUT) :: array_of_requests(count)
    TYPE(MPI_Status)                 :: array_of_statuses(*)
    INTEGER,           INTENT(OUT)   :: ierror
    INTEGER :: ireq(count), ist(MPI_STATUS_SIZE, count)
    INTEGER :: i
    DO i = 1, count
      ireq(i) = array_of_requests(i)%MPI_VAL
    END DO
    CALL f90_waitall(count, ireq, ist, ierror)
    DO i = 1, count
      array_of_requests(i)%MPI_VAL    = MPI_REQUEST_NULL%MPI_VAL
      array_of_statuses(i)%MPI_SOURCE = ist(3, i)
      array_of_statuses(i)%MPI_TAG    = ist(4, i)
      array_of_statuses(i)%MPI_ERROR  = ist(5, i)
    END DO
  END SUBROUTINE MPI_WAITALL

  SUBROUTINE MPI_TEST(request, flag, status, ierror)
    IMPLICIT NONE
    TYPE(MPI_Request), INTENT(INOUT) :: request
    LOGICAL,           INTENT(OUT)   :: flag
    TYPE(MPI_Status),  INTENT(OUT)   :: status
    INTEGER,           INTENT(OUT)   :: ierror
    INTEGER :: ist(MPI_STATUS_SIZE)
    CALL f90_test(request%MPI_VAL, flag, ist, ierror)
    status%MPI_SOURCE = ist(3)
    status%MPI_TAG    = ist(4)
    status%MPI_ERROR  = ist(5)
  END SUBROUTINE MPI_TEST

  SUBROUTINE MPI_SENDRECV(sendbuf, sendcount, sendtype, dest, sendtag, &
                          recvbuf, recvcount, recvtype, source, recvtag, &
                          comm, status, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: sendbuf
    TYPE(*), DIMENSION(*), INTENT(IN)    :: sendbuf
    INTEGER,               INTENT(IN)    :: sendcount, dest, sendtag
    TYPE(MPI_Datatype),    INTENT(IN)    :: sendtype
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: recvbuf
    TYPE(*), DIMENSION(*)                :: recvbuf
    INTEGER,               INTENT(IN)    :: recvcount, source, recvtag
    TYPE(MPI_Datatype),    INTENT(IN)    :: recvtype
    TYPE(MPI_Comm),        INTENT(IN)    :: comm
    TYPE(MPI_Status),      INTENT(OUT)   :: status
    INTEGER,               INTENT(OUT)   :: ierror
    INTEGER :: ist(MPI_STATUS_SIZE)
    CALL f90_sendrecv(sendbuf, sendcount, sendtype%MPI_VAL, dest, sendtag, &
                      recvbuf, recvcount, recvtype%MPI_VAL, source, recvtag, &
                      comm%MPI_VAL, ist, ierror)
    status%MPI_SOURCE = ist(3)
    status%MPI_TAG    = ist(4)
    status%MPI_ERROR  = ist(5)
  END SUBROUTINE MPI_SENDRECV

  !==========================================================================
  ! Derived datatype operations
  !==========================================================================

  SUBROUTINE MPI_TYPE_CREATE_STRUCT(count, array_of_blocklengths, &
                                    array_of_displacements, array_of_types, &
                                    newtype, ierror)
    IMPLICIT NONE
    INTEGER,            INTENT(IN)  :: count
    INTEGER,            INTENT(IN)  :: array_of_blocklengths(count)
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(IN) :: array_of_displacements(count)
    TYPE(MPI_Datatype), INTENT(IN)  :: array_of_types(count)
    TYPE(MPI_Datatype), INTENT(OUT) :: newtype
    INTEGER,            INTENT(OUT) :: ierror
    INTEGER :: itypes(count)
    INTEGER :: i
    DO i = 1, count
      itypes(i) = array_of_types(i)%MPI_VAL
    END DO
    CALL f90_type_create_struct(count, array_of_blocklengths, &
                                array_of_displacements, itypes, &
                                newtype%MPI_VAL, ierror)
  END SUBROUTINE MPI_TYPE_CREATE_STRUCT

  SUBROUTINE MPI_TYPE_COMMIT(datatype, ierror)
    IMPLICIT NONE
    TYPE(MPI_Datatype), INTENT(INOUT) :: datatype
    INTEGER,            INTENT(OUT)   :: ierror
    CALL f90_type_commit(datatype%MPI_VAL, ierror)
  END SUBROUTINE MPI_TYPE_COMMIT

  SUBROUTINE MPI_TYPE_FREE(datatype, ierror)
    IMPLICIT NONE
    TYPE(MPI_Datatype), INTENT(INOUT) :: datatype
    INTEGER,            INTENT(OUT)   :: ierror
    CALL f90_type_free(datatype%MPI_VAL, ierror)
  END SUBROUTINE MPI_TYPE_FREE

  SUBROUTINE MPI_TYPE_SIZE(datatype, size, ierror)
    IMPLICIT NONE
    TYPE(MPI_Datatype), INTENT(IN)  :: datatype
    INTEGER,            INTENT(OUT) :: size, ierror
    CALL f90_type_size(datatype%MPI_VAL, size, ierror)
  END SUBROUTINE MPI_TYPE_SIZE

  SUBROUTINE MPI_TYPE_GET_EXTENT(datatype, lb, extent, ierror)
    IMPLICIT NONE
    TYPE(MPI_Datatype),             INTENT(IN)  :: datatype
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(OUT) :: lb, extent
    INTEGER,                        INTENT(OUT) :: ierror
    CALL f90_type_get_extent(datatype%MPI_VAL, lb, extent, ierror)
  END SUBROUTINE MPI_TYPE_GET_EXTENT

  SUBROUTINE MPI_TYPE_CONTIGUOUS(count, oldtype, newtype, ierror)
    IMPLICIT NONE
    INTEGER,            INTENT(IN)  :: count
    TYPE(MPI_Datatype), INTENT(IN)  :: oldtype
    TYPE(MPI_Datatype), INTENT(OUT) :: newtype
    INTEGER,            INTENT(OUT) :: ierror
    CALL f90_type_contiguous(count, oldtype%MPI_VAL, newtype%MPI_VAL, ierror)
  END SUBROUTINE MPI_TYPE_CONTIGUOUS

  SUBROUTINE MPI_TYPE_VECTOR(count, blocklength, stride, oldtype, newtype, ierror)
    IMPLICIT NONE
    INTEGER,            INTENT(IN)  :: count, blocklength, stride
    TYPE(MPI_Datatype), INTENT(IN)  :: oldtype
    TYPE(MPI_Datatype), INTENT(OUT) :: newtype
    INTEGER,            INTENT(OUT) :: ierror
    CALL f90_type_vector(count, blocklength, stride, oldtype%MPI_VAL, &
                         newtype%MPI_VAL, ierror)
  END SUBROUTINE MPI_TYPE_VECTOR

  SUBROUTINE MPI_TYPE_CREATE_SUBARRAY(ndims, array_of_sizes, array_of_subsizes, &
                                      array_of_starts, order, oldtype, newtype, ierror)
    IMPLICIT NONE
    INTEGER,            INTENT(IN)  :: ndims
    INTEGER,            INTENT(IN)  :: array_of_sizes(*), array_of_subsizes(*), &
                                       array_of_starts(*)
    INTEGER,            INTENT(IN)  :: order
    TYPE(MPI_Datatype), INTENT(IN)  :: oldtype
    TYPE(MPI_Datatype), INTENT(OUT) :: newtype
    INTEGER,            INTENT(OUT) :: ierror
    CALL f90_type_create_subarray(ndims, array_of_sizes, array_of_subsizes, &
                                  array_of_starts, order, oldtype%MPI_VAL, &
                                  newtype%MPI_VAL, ierror)
  END SUBROUTINE MPI_TYPE_CREATE_SUBARRAY

  SUBROUTINE MPI_TYPE_CREATE_RESIZED(oldtype, lb, extent, newtype, ierror)
    IMPLICIT NONE
    TYPE(MPI_Datatype),             INTENT(IN)  :: oldtype
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(IN)  :: lb, extent
    TYPE(MPI_Datatype),             INTENT(OUT) :: newtype
    INTEGER,                        INTENT(OUT) :: ierror
    CALL f90_type_create_resized(oldtype%MPI_VAL, lb, extent, newtype%MPI_VAL, &
                                 ierror)
  END SUBROUTINE MPI_TYPE_CREATE_RESIZED

  !==========================================================================
  ! Info operations
  !==========================================================================

  SUBROUTINE MPI_INFO_CREATE(info, ierror)
    IMPLICIT NONE
    TYPE(MPI_Info), INTENT(OUT) :: info
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_info_create(info%MPI_VAL, ierror)
  END SUBROUTINE MPI_INFO_CREATE

  SUBROUTINE MPI_INFO_FREE(info, ierror)
    IMPLICIT NONE
    TYPE(MPI_Info), INTENT(INOUT) :: info
    INTEGER,        INTENT(OUT)   :: ierror
    CALL f90_info_free(info%MPI_VAL, ierror)
  END SUBROUTINE MPI_INFO_FREE

  SUBROUTINE MPI_INFO_SET(info, key, value, ierror)
    IMPLICIT NONE
    TYPE(MPI_Info),  INTENT(IN)  :: info
    CHARACTER(LEN=*),INTENT(IN)  :: key, value
    INTEGER,         INTENT(OUT) :: ierror
    CALL f90_info_set(info%MPI_VAL, key, value, ierror)
  END SUBROUTINE MPI_INFO_SET

  SUBROUTINE MPI_INFO_GET(info, key, valuelen, value, flag, ierror)
    IMPLICIT NONE
    TYPE(MPI_Info),  INTENT(IN)  :: info
    CHARACTER(LEN=*),INTENT(IN)  :: key
    INTEGER,         INTENT(IN)  :: valuelen
    CHARACTER(LEN=*),INTENT(OUT) :: value
    LOGICAL,         INTENT(OUT) :: flag
    INTEGER,         INTENT(OUT) :: ierror
    CALL f90_info_get(info%MPI_VAL, key, valuelen, value, flag, ierror)
  END SUBROUTINE MPI_INFO_GET

  SUBROUTINE MPI_INFO_DUP(info, newinfo, ierror)
    IMPLICIT NONE
    TYPE(MPI_Info), INTENT(IN)  :: info
    TYPE(MPI_Info), INTENT(OUT) :: newinfo
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_info_dup(info%MPI_VAL, newinfo%MPI_VAL, ierror)
  END SUBROUTINE MPI_INFO_DUP

  !==========================================================================
  ! Window (RMA / shared memory) operations
  !==========================================================================

  SUBROUTINE MPI_WIN_FREE(win, ierror)
    IMPLICIT NONE
    TYPE(MPI_Win), INTENT(INOUT) :: win
    INTEGER,       INTENT(OUT)   :: ierror
    CALL f90_win_free(win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_FREE

  SUBROUTINE MPI_WIN_SYNC(win, ierror)
    IMPLICIT NONE
    TYPE(MPI_Win), INTENT(IN)  :: win
    INTEGER,       INTENT(OUT) :: ierror
    CALL f90_win_sync(win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_SYNC

  SUBROUTINE MPI_WIN_LOCK_ALL(assert, win, ierror)
    IMPLICIT NONE
    INTEGER,       INTENT(IN)  :: assert
    TYPE(MPI_Win), INTENT(IN)  :: win
    INTEGER,       INTENT(OUT) :: ierror
    CALL f90_win_lock_all(assert, win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_LOCK_ALL

  SUBROUTINE MPI_WIN_UNLOCK_ALL(win, ierror)
    IMPLICIT NONE
    TYPE(MPI_Win), INTENT(IN)  :: win
    INTEGER,       INTENT(OUT) :: ierror
    CALL f90_win_unlock_all(win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_UNLOCK_ALL

  SUBROUTINE MPI_WIN_FLUSH_ALL(win, ierror)
    IMPLICIT NONE
    TYPE(MPI_Win), INTENT(IN)  :: win
    INTEGER,       INTENT(OUT) :: ierror
    CALL f90_win_flush_all(win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_FLUSH_ALL

  SUBROUTINE MPI_WIN_FENCE(assert, win, ierror)
    IMPLICIT NONE
    INTEGER,       INTENT(IN)  :: assert
    TYPE(MPI_Win), INTENT(IN)  :: win
    INTEGER,       INTENT(OUT) :: ierror
    CALL f90_win_fence(assert, win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_FENCE

  SUBROUTINE MPI_WIN_CREATE(base, size, disp_unit, info, comm, win, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: base
    TYPE(*), DIMENSION(*), ASYNCHRONOUS  :: base
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(IN) :: size
    INTEGER,       INTENT(IN)  :: disp_unit
    TYPE(MPI_Info),INTENT(IN)  :: info
    TYPE(MPI_Comm),INTENT(IN)  :: comm
    TYPE(MPI_Win), INTENT(OUT) :: win
    INTEGER,       INTENT(OUT) :: ierror
    CALL f90_win_create(base, size, disp_unit, info%MPI_VAL, comm%MPI_VAL, &
                        win%MPI_VAL, ierror)
  END SUBROUTINE MPI_WIN_CREATE

  ! MPI_Win_allocate_shared wrapper: allocate shared-memory window.
  ! The legacy MS-MPI binding returns BASEPTR as INTEGER(MPI_ADDRESS_KIND)
  ! (a raw pointer value).  We receive it as such and bit-transfer it to
  ! TYPE(C_PTR) so that callers can use C_F_POINTER on it.
  ! Exported under a PICLas-internal name (not MPI_WIN_ALLOCATE_SHARED):
  ! a real-MPI PETSc's Fortran module exports the standard name, and the
  ! blanket re-export via MOD_Globals would make it ambiguous in every
  ! file that also uses PETSc.  Sole caller is src/mpi/mpi_shared.f90,
  ! which rename-imports it back to the standard name.
  SUBROUTINE PICLAS_WIN_ALLOCATE_SHARED(size, disp_unit, info, comm, baseptr, win, ierror)
    USE, INTRINSIC :: ISO_C_BINDING, ONLY: C_PTR, C_NULL_PTR
    IMPLICIT NONE
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(IN)  :: size
    INTEGER,        INTENT(IN)  :: disp_unit
    TYPE(MPI_Info), INTENT(IN)  :: info
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    TYPE(C_PTR),    INTENT(OUT) :: baseptr
    TYPE(MPI_Win),  INTENT(OUT) :: win
    INTEGER,        INTENT(OUT) :: ierror
    INTEGER(KIND=MPI_ADDRESS_KIND) :: baseptr_raw
    CALL f90_win_allocate_shared(size, disp_unit, info%MPI_VAL, comm%MPI_VAL, &
                                 baseptr_raw, win%MPI_VAL, ierror)
    baseptr = TRANSFER(baseptr_raw, C_NULL_PTR)
  END SUBROUTINE PICLAS_WIN_ALLOCATE_SHARED

  ! MPI_Win_shared_query wrapper: query shared-memory window address for a
  ! given rank.  PICLas-internal name for the same reason as above.
  SUBROUTINE PICLAS_WIN_SHARED_QUERY(win, rank, size, disp_unit, baseptr, ierror)
    USE, INTRINSIC :: ISO_C_BINDING, ONLY: C_PTR, C_NULL_PTR
    IMPLICIT NONE
    TYPE(MPI_Win), INTENT(IN)   :: win
    INTEGER,       INTENT(IN)   :: rank
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(OUT) :: size
    INTEGER,       INTENT(OUT)  :: disp_unit
    TYPE(C_PTR),   INTENT(OUT)  :: baseptr
    INTEGER,       INTENT(OUT)  :: ierror
    INTEGER(KIND=MPI_ADDRESS_KIND) :: baseptr_raw
    CALL f90_win_shared_query(win%MPI_VAL, rank, size, disp_unit, baseptr_raw, ierror)
    baseptr = TRANSFER(baseptr_raw, C_NULL_PTR)
  END SUBROUTINE PICLAS_WIN_SHARED_QUERY

  !==========================================================================
  ! Miscellaneous
  !==========================================================================

  SUBROUTINE MPI_ABORT(comm, errorcode, ierror)
    IMPLICIT NONE
    TYPE(MPI_Comm), INTENT(IN)  :: comm
    INTEGER,        INTENT(IN)  :: errorcode
    INTEGER,        INTENT(OUT) :: ierror
    CALL f90_abort(comm%MPI_VAL, errorcode, ierror)
  END SUBROUTINE MPI_ABORT

  SUBROUTINE MPI_GET_ADDRESS(location, address, ierror)
    IMPLICIT NONE
    !GCC$ ATTRIBUTES NO_ARG_CHECK :: location
    TYPE(*), DIMENSION(*), ASYNCHRONOUS  :: location
    INTEGER(KIND=MPI_ADDRESS_KIND), INTENT(OUT) :: address
    INTEGER,                        INTENT(OUT) :: ierror
    CALL f90_get_address(location, address, ierror)
  END SUBROUTINE MPI_GET_ADDRESS

  SUBROUTINE MPI_ERROR_STRING(errorcode, string, resultlen, ierror)
    IMPLICIT NONE
    INTEGER,         INTENT(IN)  :: errorcode
    CHARACTER(LEN=*),INTENT(OUT) :: string
    INTEGER,         INTENT(OUT) :: resultlen, ierror
    CALL f90_error_string(errorcode, string, resultlen, ierror)
  END SUBROUTINE MPI_ERROR_STRING

  SUBROUTINE MPI_GET_COUNT(status, datatype, count, ierror)
    IMPLICIT NONE
    TYPE(MPI_Status),   INTENT(IN)  :: status
    TYPE(MPI_Datatype), INTENT(IN)  :: datatype
    INTEGER,            INTENT(OUT) :: count, ierror
    INTEGER :: ist(MPI_STATUS_SIZE)
    ist    = 0
    ist(3) = status%MPI_SOURCE
    ist(4) = status%MPI_TAG
    ist(5) = status%MPI_ERROR
    CALL f90_get_count(ist, datatype%MPI_VAL, count, ierror)
  END SUBROUTINE MPI_GET_COUNT

  SUBROUTINE MPI_OP_CREATE(function, commute, op, ierror)
    IMPLICIT NONE
    EXTERNAL         :: function
    LOGICAL,         INTENT(IN)  :: commute
    TYPE(MPI_Op),    INTENT(OUT) :: op
    INTEGER,         INTENT(OUT) :: ierror
    CALL f90_op_create(function, commute, op%MPI_VAL, ierror)
  END SUBROUTINE MPI_OP_CREATE

  SUBROUTINE MPI_OP_FREE(op, ierror)
    IMPLICIT NONE
    TYPE(MPI_Op), INTENT(INOUT) :: op
    INTEGER,      INTENT(OUT)   :: ierror
    CALL f90_op_free(op%MPI_VAL, ierror)
  END SUBROUTINE MPI_OP_FREE

  ! --- Equality operators for handle types ---
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Comm_eq(a,b)
    TYPE(MPI_Comm), INTENT(IN) :: a, b
    MPI_Comm_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Comm_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Comm_neq(a,b)
    TYPE(MPI_Comm), INTENT(IN) :: a, b
    MPI_Comm_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Comm_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Win_eq(a,b)
    TYPE(MPI_Win), INTENT(IN) :: a, b
    MPI_Win_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Win_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Win_neq(a,b)
    TYPE(MPI_Win), INTENT(IN) :: a, b
    MPI_Win_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Win_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Request_eq(a,b)
    TYPE(MPI_Request), INTENT(IN) :: a, b
    MPI_Request_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Request_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Request_neq(a,b)
    TYPE(MPI_Request), INTENT(IN) :: a, b
    MPI_Request_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Request_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Info_eq(a,b)
    TYPE(MPI_Info), INTENT(IN) :: a, b
    MPI_Info_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Info_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Info_neq(a,b)
    TYPE(MPI_Info), INTENT(IN) :: a, b
    MPI_Info_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Info_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Datatype_eq(a,b)
    TYPE(MPI_Datatype), INTENT(IN) :: a, b
    MPI_Datatype_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Datatype_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Datatype_neq(a,b)
    TYPE(MPI_Datatype), INTENT(IN) :: a, b
    MPI_Datatype_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Datatype_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Op_eq(a,b)
    TYPE(MPI_Op), INTENT(IN) :: a, b
    MPI_Op_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Op_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Op_neq(a,b)
    TYPE(MPI_Op), INTENT(IN) :: a, b
    MPI_Op_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Op_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Group_eq(a,b)
    TYPE(MPI_Group), INTENT(IN) :: a, b
    MPI_Group_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Group_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Group_neq(a,b)
    TYPE(MPI_Group), INTENT(IN) :: a, b
    MPI_Group_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Group_neq

  PURE ELEMENTAL LOGICAL FUNCTION MPI_Errhandler_eq(a,b)
    TYPE(MPI_Errhandler), INTENT(IN) :: a, b
    MPI_Errhandler_eq = (a%MPI_VAL == b%MPI_VAL)
  END FUNCTION MPI_Errhandler_eq
  PURE ELEMENTAL LOGICAL FUNCTION MPI_Errhandler_neq(a,b)
    TYPE(MPI_Errhandler), INTENT(IN) :: a, b
    MPI_Errhandler_neq = (a%MPI_VAL /= b%MPI_VAL)
  END FUNCTION MPI_Errhandler_neq

  FUNCTION MPI_WTIME() RESULT(t)
    IMPLICIT NONE
    DOUBLE PRECISION :: t
    t = f90_wtime()
  END FUNCTION MPI_WTIME

  FUNCTION MPI_WTICK() RESULT(t)
    IMPLICIT NONE
    DOUBLE PRECISION :: t
    t = f90_wtick()
  END FUNCTION MPI_WTICK

END MODULE mpi_f08
