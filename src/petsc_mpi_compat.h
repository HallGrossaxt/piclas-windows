/* =========================================================================
 * petsc_mpi_compat.h — PETSc sequential + MS-MPI coexistence header
 * =========================================================================
 * Include this IMMEDIATELY AFTER #include "petsc/finclude/petsc.h" in every
 * Fortran source file that also calls real MPI functions (USE_MPI builds).
 *
 * Problem
 * -------
 * MSYS2's PETSc is a sequential (no-MPI) build.  Its Fortran include chain
 *
 *   petsc/finclude/petsc.h  →  petscsys.h  →  mpiunifdef.h
 *
 * unconditionally #defines every MPI_xxx symbol to PETSC_MPI_xxx.  In a
 * USE_MPI build, any use of MPI_BCAST, MPI_WTIME, etc. in the same source
 * file is silently renamed to PETSC_MPI_BCAST, PETSC_MPI_WTIME, ...
 * which are unknown symbols → compile error.
 *
 * Fix
 * ---
 * #undef all 138 macros (3 case variants × 46 functions) set by
 * mpiunifdef.h so that the MPI_xxx identifiers in subsequent source text
 * refer to the real symbols exported by USE mpi_f08 / USE mpi and linked
 * from libmsmpi.dll.a.
 *
 * Link-time correctness
 * ---------------------
 *   PICLas source code → calls real MPI_xxx   (from libmsmpi.dll.a)
 *   PETSc library code → calls PETSC_MPI_xxx  (from libpetsc sequential stubs)
 *   No symbol overlap → no conflict.
 *
 * Runtime caveat
 * --------------
 * PETSc runs in sequential (single-rank) mode on each MPI process.
 * Cross-rank PETSc parallel assembly is not available with this combination.
 * PICLas particle/field MPI communication is fully unaffected.
 * ========================================================================= */

#if defined(USE_MPI) && defined(MPIUNIFDEF_H)

/* --- Mixed-case variants (as they appear in C/Fortran source) ----------- */
#undef MPI_Init
#undef MPI_Finalize
#undef MPI_Comm_size
#undef MPI_Comm_rank
#undef MPI_Abort
#undef MPI_Reduce
#undef MPI_Allreduce
#undef MPI_Barrier
#undef MPI_Bcast
#undef MPI_Gather
#undef MPI_Allgather
#undef MPI_Comm_split
#undef MPI_Scan
#undef MPI_Send
#undef MPI_Recv
#undef MPI_Reduce_scatter
#undef MPI_Irecv
#undef MPI_Isend
#undef MPI_Sendrecv
#undef MPI_Test
#undef MPI_Waitall
#undef MPI_Waitany
#undef MPI_Allgatherv
#undef MPI_Alltoallv
#undef MPI_Comm_create
#undef MPI_Address
#undef MPI_Pack
#undef MPI_Unpack
#undef MPI_Pack_size
#undef MPI_Type_struct
#undef MPI_Type_commit
#undef MPI_Wtime
#undef MPI_Cancel
#undef MPI_Comm_dup
#undef MPI_Comm_free
#undef MPI_Get_count
#undef MPI_Get_processor_name
#undef MPI_Initialized
#undef MPI_Iprobe
#undef MPI_Probe
#undef MPI_Request_free
#undef MPI_Ssend
#undef MPI_Wait
#undef MPI_Comm_group
#undef MPI_Exscan

/* --- UPPERCASE variants ------------------------------------------------- */
#undef MPI_INIT
#undef MPI_FINALIZE
#undef MPI_COMM_SIZE
#undef MPI_COMM_RANK
#undef MPI_ABORT
#undef MPI_REDUCE
#undef MPI_ALLREDUCE
#undef MPI_BARRIER
#undef MPI_BCAST
#undef MPI_GATHER
#undef MPI_ALLGATHER
#undef MPI_COMM_SPLIT
#undef MPI_SCAN
#undef MPI_SEND
#undef MPI_RECV
#undef MPI_REDUCE_SCATTER
#undef MPI_IRECV
#undef MPI_ISEND
#undef MPI_SENDRECV
#undef MPI_TEST
#undef MPI_WAITALL
#undef MPI_WAITANY
#undef MPI_ALLGATHERV
#undef MPI_ALLTOALLV
#undef MPI_COMM_CREATE
#undef MPI_ADDRESS
#undef MPI_PACK
#undef MPI_UNPACK
#undef MPI_PACK_SIZE
#undef MPI_TYPE_STRUCT
#undef MPI_TYPE_COMMIT
#undef MPI_WTIME
#undef MPI_CANCEL
#undef MPI_COMM_DUP
#undef MPI_COMM_FREE
#undef MPI_GET_COUNT
#undef MPI_GET_PROCESSOR_NAME
#undef MPI_INITIALIZED
#undef MPI_IPROBE
#undef MPI_PROBE
#undef MPI_REQUEST_FREE
#undef MPI_SSEND
#undef MPI_WAIT
#undef MPI_COMM_GROUP
#undef MPI_EXSCAN

/* --- lowercase variants ------------------------------------------------- */
#undef mpi_init
#undef mpi_finalize
#undef mpi_comm_size
#undef mpi_comm_rank
#undef mpi_abort
#undef mpi_reduce
#undef mpi_allreduce
#undef mpi_barrier
#undef mpi_bcast
#undef mpi_gather
#undef mpi_allgather
#undef mpi_comm_split
#undef mpi_scan
#undef mpi_send
#undef mpi_recv
#undef mpi_reduce_scatter
#undef mpi_irecv
#undef mpi_isend
#undef mpi_sendrecv
#undef mpi_test
#undef mpi_waitall
#undef mpi_waitany
#undef mpi_allgatherv
#undef mpi_alltoallv
#undef mpi_comm_create
#undef mpi_address
#undef mpi_pack
#undef mpi_unpack
#undef mpi_pack_size
#undef mpi_type_struct
#undef mpi_type_commit
#undef mpi_wtime
#undef mpi_cancel
#undef mpi_comm_dup
#undef mpi_comm_free
#undef mpi_get_count
#undef mpi_get_processor_name
#undef mpi_initialized
#undef mpi_iprobe
#undef mpi_probe
#undef mpi_request_free
#undef mpi_ssend
#undef mpi_wait
#undef mpi_comm_group
#undef mpi_exscan

/* MPIUNI_FInt is a Fortran-syntax type macro — not used in PICLas source */
#undef MPIUNI_FInt

#endif /* USE_MPI && MPIUNIFDEF_H */
