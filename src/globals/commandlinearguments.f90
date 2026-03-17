!=================================================================================================================================
! Copyright (c) 2010-2016  Prof. Claus-Dieter Munz
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "piclas.h"

!=================================================================================================================================
!> Module to handle commandline arguments
!=================================================================================================================================
MODULE MOD_Commandline_Arguments
USE ISO_C_BINDING, ONLY: C_INT, C_CHAR, C_NULL_CHAR
IMPLICIT NONE

! Global variables for command line argument parsing
INTEGER                              :: nArgs              ! number of command line arguments
CHARACTER(LEN=255),ALLOCATABLE       :: Args(:)

! Interface to the Win32 glob expansion helper (glob_windows.c).
! On non-Windows platforms the C function is compiled as a no-op stub that
! always returns 0, so the code path is never taken on Linux/macOS (where
! the shell already expands wildcards before the program starts).
INTERFACE
  FUNCTION glob_expand_c(pattern, results, results_len) BIND(C, NAME='glob_expand_c')
    USE ISO_C_BINDING, ONLY: C_INT, C_CHAR
    IMPLICIT NONE
    CHARACTER(KIND=C_CHAR), INTENT(IN)        :: pattern(*)    ! null-terminated pattern
    CHARACTER(KIND=C_CHAR), INTENT(OUT)       :: results(*)    ! null-separated result list
    INTEGER(KIND=C_INT),    VALUE, INTENT(IN) :: results_len   ! size of results buffer
    INTEGER(KIND=C_INT)                       :: glob_expand_c ! number of matches found
  END FUNCTION glob_expand_c
END INTERFACE

INTERFACE ParseCommandlineArguments
  MODULE PROCEDURE ParseCommandlineArguments
END INTERFACE ParseCommandlineArguments

!==================================================================================================================================
CONTAINS

!==================================================================================================================================
!> Reads all commandline arguments.
!> On Windows, arguments that contain '*' or '?' are expanded using the Win32
!> FindFirstFile API (glob_windows.c) so that wildcard patterns work from any
!> shell (cmd.exe, PowerShell, or MSYS2 bash).
!==================================================================================================================================
SUBROUTINE ParseCommandlineArguments()
! MODULES
USE MOD_Globals
USE MOD_StringTools     ,ONLY: STRICMP
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: iArg, iRaw, nArgs_tmp, nRaw
CHARACTER(LEN=255)               :: tmp
LOGICAL,      ALLOCATABLE        :: alreadyRead(:)
CHARACTER(LEN=255), ALLOCATABLE  :: rawArgs(:)   ! raw (unexpanded) remaining args
! Glob expansion workspace (Windows only; reused for count pass and fill pass)
INTEGER(C_INT)                   :: nExpanded
CHARACTER(KIND=C_CHAR)           :: c_pattern(256)
CHARACTER(KIND=C_CHAR)           :: c_results(65536)
INTEGER                          :: j, k, charPos, entryLen
!==================================================================================================================================
! Get number of command line arguments
nArgs_tmp = COMMAND_ARGUMENT_COUNT()
ALLOCATE(alreadyRead(nArgs_tmp))
alreadyRead = .FALSE.

! --- Pass 1: identify and remove keyword arguments (--help, --markdown) ---
!doGenerateUnittestReferenceData = .FALSE.
!doPrintHelp = 0
nArgs = nArgs_tmp
DO iArg = 1, nArgs_tmp
  CALL GET_COMMAND_ARGUMENT(iArg, tmp)
  IF (STRICMP(tmp, "--help").OR.STRICMP(tmp,"-h")) THEN
    doPrintHelp = 1
    alreadyRead(iArg) = .TRUE.
    nArgs = nArgs - 1
  END IF
  IF (STRICMP(tmp, "--markdown")) THEN
    doPrintHelp = 2
    alreadyRead(iArg) = .TRUE.
    nArgs = nArgs - 1
  END IF
END DO

! --- Collect the remaining (non-keyword) raw arguments ---
nRaw = MAX(1, nArgs)
ALLOCATE(rawArgs(nRaw))
rawArgs(1) = ""
nRaw = 0
DO iArg = 1, nArgs_tmp
  IF (.NOT.alreadyRead(iArg)) THEN
    nRaw = nRaw + 1
    CALL GET_COMMAND_ARGUMENT(iArg, rawArgs(nRaw))
    alreadyRead(iArg) = .TRUE.
  END IF
END DO
DEALLOCATE(alreadyRead)

! --- Pass 2 (count): determine total number of Args after glob expansion ---
nArgs = 0
DO iRaw = 1, nRaw
  tmp = rawArgs(iRaw)
  IF (INDEX(tmp,'*') .GT. 0 .OR. INDEX(tmp,'?') .GT. 0) THEN
    ! Build null-terminated C string from Fortran string
    DO j = 1, LEN_TRIM(tmp)
      c_pattern(j) = tmp(j:j)
    END DO
    c_pattern(LEN_TRIM(tmp)+1) = C_NULL_CHAR
    nExpanded = glob_expand_c(c_pattern, c_results, 65536_C_INT)
    IF (nExpanded .GT. 0) THEN
      nArgs = nArgs + INT(nExpanded)
    ELSE
      nArgs = nArgs + 1   ! no match: keep the literal string
    END IF
  ELSE
    nArgs = nArgs + 1
  END IF
END DO

! --- Allocate Args with the correct (expanded) size ---
nArgs = MAX(1, nArgs)
ALLOCATE(Args(nArgs))
Args(1) = ""
nArgs = 0

! --- Pass 3 (fill): populate Args, expanding wildcards ---
DO iRaw = 1, nRaw
  tmp = rawArgs(iRaw)
  IF (INDEX(tmp,'*') .GT. 0 .OR. INDEX(tmp,'?') .GT. 0) THEN
    DO j = 1, LEN_TRIM(tmp)
      c_pattern(j) = tmp(j:j)
    END DO
    c_pattern(LEN_TRIM(tmp)+1) = C_NULL_CHAR
    nExpanded = glob_expand_c(c_pattern, c_results, 65536_C_INT)
    IF (nExpanded .GT. 0) THEN
      ! Parse the null-separated result list
      charPos = 1
      DO j = 1, INT(nExpanded)
        ! Find the length of this entry (scan to the next null byte)
        entryLen = 0
        DO WHILE (charPos + entryLen <= 65536)
          IF (c_results(charPos + entryLen) == C_NULL_CHAR) EXIT
          entryLen = entryLen + 1
        END DO
        nArgs = nArgs + 1
        Args(nArgs) = ' '   ! blank-fill
        DO k = 1, entryLen
          Args(nArgs)(k:k) = c_results(charPos + k - 1)
        END DO
        charPos = charPos + entryLen + 1  ! advance past the null terminator
      END DO
    ELSE
      ! Glob found no matches: pass the literal pattern through unchanged
      nArgs = nArgs + 1
      Args(nArgs) = tmp
    END IF
  ELSE
    nArgs = nArgs + 1
    Args(nArgs) = tmp
  END IF
END DO

DEALLOCATE(rawArgs)
END SUBROUTINE ParseCommandlineArguments

SUBROUTINE FinalizeCommandlineArguments()
IMPLICIT NONE
!===================================================================================================================================
SDEALLOCATE(Args)
END SUBROUTINE FinalizeCommandlineArguments

END MODULE MOD_Commandline_Arguments
