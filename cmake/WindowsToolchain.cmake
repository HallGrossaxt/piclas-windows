# =========================================================================
# WindowsToolchain.cmake
#
# Optional CMake toolchain file for building PICLas on Windows with
# MSYS2/MinGW-w64. Pass this file to CMake via:
#
#   cmake -DCMAKE_TOOLCHAIN_FILE=cmake/WindowsToolchain.cmake ..
#
# Requirements (install via MSYS2 pacman):
#   pacman -S mingw-w64-x86_64-gcc-fortran
#   pacman -S mingw-w64-x86_64-cmake
#   pacman -S mingw-w64-x86_64-hdf5           (or let PICLas self-build it)
#   pacman -S mingw-w64-x86_64-openblas       (or let PICLas self-build it)
#   pacman -S mingw-w64-x86_64-msmpi          (optional, for MPI support)
#
# Alternatively, install Microsoft MPI (MS-MPI) SDK from:
#   https://learn.microsoft.com/en-us/message-passing-interface/microsoft-mpi
# =========================================================================

SET(CMAKE_SYSTEM_NAME Windows)
SET(CMAKE_SYSTEM_PROCESSOR x86_64)

# Prefer MinGW-w64 compilers from MSYS2
FIND_PROGRAM(CMAKE_C_COMPILER       NAMES x86_64-w64-mingw32-gcc  gcc  DOC "C compiler")
FIND_PROGRAM(CMAKE_CXX_COMPILER     NAMES x86_64-w64-mingw32-g++  g++  DOC "C++ compiler")
FIND_PROGRAM(CMAKE_Fortran_COMPILER NAMES x86_64-w64-mingw32-gfortran gfortran DOC "Fortran compiler")

# Ensure we target native Windows (not MSYS2 POSIX layer)
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
