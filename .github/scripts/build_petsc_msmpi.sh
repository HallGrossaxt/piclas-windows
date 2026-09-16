#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_petsc_msmpi.sh — build PETSc --with-mpi against MS-MPI for the
# PIC-MC + PETSc Windows build (guide §16.32). Run from the MSYS2 UCRT64 shell.
#
# The MSYS2 PETSc package is --with-mpi=0 (sequential/MPIUNI), which aborts
# above one rank. This builds a parallel PETSc against the MSYS2 MS-MPI import
# lib, mirroring the locally-proven arch-msmpi-gnu.py options exactly.
#
# Environment:
#   PETSC_VERSION  PETSc release to build            (default 3.24.5)
#   PETSC_PREFIX   install dir, MSYS path (required) e.g. /c/…/petsc-msmpi
#   PETSC_SRC      source dir, MSYS path             (default $PWD/petsc-src)
#   MINGW_PREFIX   UCRT64 prefix, MSYS path          (set by setup-msys2, e.g. /ucrt64)
#
# Notes / gotchas (all learned building this locally):
#   * PETSc configure needs the MSYS /usr/bin/python3 (the ucrt64 python is
#     unsuitable). Install the base-MSYS 'python' and 'make' packages.
#   * --with-hwloc=0 is required on Windows (hwloc pid=HANDLE vs getpid()/int).
#   * --with-mpi-f90module-visibility=0 is MANDATORY: otherwise petscsys.mod
#     re-exports MS-MPI's legacy mpi.mod and every MPI name goes ambiguous
#     against PICLas's mpi_f08 shim.
#   * PETSc mis-derives the import name and writes "-lmsmpi.dll" into petsc.pc;
#     patch it back to "-lmsmpi" after install.
#   * --with-debugging=0 ALONE DOES NOT GIVE AN OPTIMISED BUILD. Without an explicit
#     COPTFLAGS/FOPTFLAGS, PETSc silently falls back to "-g -O", i.e. -O1 with debug info
#     and generic arch. Every release before this script grew PETSC_OPTFLAGS shipped an
#     -O1 PETSc inside the PIC-MC bundle. Verify after building with:
#         grep '^CC_FLAGS' $PREFIX/lib/petsc/conf/petscvariables
#     Dropping -g also shrinks libpetsc.a substantially (130 MB at -g -O vs 45 MB at -O3).
# ---------------------------------------------------------------------------
set -euo pipefail

PETSC_VERSION="${PETSC_VERSION:-3.24.5}"
PREFIX="${PETSC_PREFIX:?set PETSC_PREFIX (MSYS path to install dir)}"
SRC="${PETSC_SRC:-$PWD/petsc-src}"
MINGW="${MINGW_PREFIX:?MINGW_PREFIX not set (run in the MSYS2 UCRT64 shell)}"

# Optimisation flags for PETSc's own C/Fortran. MUST STAY PORTABLE: these binaries are
# redistributed, so -march=native would produce a bundle that crashes with an illegal
# instruction on any machine older than the CI runner. x86-64-v2 matches the floor the
# CMake presets already target (PICLAS_INSTRUCTION in CMakePresets.json) -- keep the two
# in step if that floor is ever raised.
PETSC_OPTFLAGS="${PETSC_OPTFLAGS:--O3 -march=x86-64-v2 -mtune=generic}"

echo "=== PETSc $PETSC_VERSION  ->  $PREFIX  (MINGW=$MINGW) ==="

# --- fetch source (release tarball) ---------------------------------------
if [ ! -f "$SRC/configure" ]; then
  mkdir -p "$SRC"
  url="https://web.cels.anl.gov/projects/petsc/download/release-snapshots/petsc-${PETSC_VERSION}.tar.gz"
  echo "Downloading $url"
  curl -fL --retry 5 --retry-delay 10 "$url" -o "$SRC/../petsc.tar.gz"
  tar -xzf "$SRC/../petsc.tar.gz" -C "$SRC" --strip-components=1
fi

# --- configure (mirrors arch-msmpi-gnu.py) --------------------------------
cd "$SRC"
/usr/bin/python3 ./configure \
  PETSC_ARCH=mswin-msmpi \
  --prefix="$PREFIX" \
  --with-cc=gcc \
  --with-cxx=0 \
  --with-fc=gfortran \
  "FFLAGS=-I${MINGW}/include -fallow-invalid-boz -fallow-argument-mismatch" \
  "FPPFLAGS=-I${MINGW}/include" \
  --with-mpi=1 \
  --with-mpi-include="${MINGW}/include" \
  --with-mpi-lib="${MINGW}/lib/libmsmpi.dll.a" \
  --with-mpi-f90module-visibility=0 \
  --with-openblas-dir="${MINGW}" \
  --with-single-library=1 \
  --with-shared-libraries=0 \
  --with-windows-graphics=0 \
  --with-x=0 \
  --with-hwloc=0 \
  --with-pthread=0 \
  --with-openmp=0 \
  --with-precision=double \
  --with-scalar-type=real \
  --with-debugging=0 \
  COPTFLAGS="$PETSC_OPTFLAGS" \
  FOPTFLAGS="$PETSC_OPTFLAGS" \
  CXXOPTFLAGS="$PETSC_OPTFLAGS"

# --- build + install ------------------------------------------------------
make PETSC_DIR="$SRC" PETSC_ARCH=mswin-msmpi all
make PETSC_DIR="$SRC" PETSC_ARCH=mswin-msmpi install

# --- fix the pkg-config import name (-lmsmpi.dll -> -lmsmpi) ---------------
pc="$PREFIX/lib/pkgconfig/petsc.pc"
if [ -f "$pc" ]; then
  sed -i 's/-lmsmpi\.dll/-lmsmpi/g' "$pc"
  echo "patched $pc"
fi

test -f "$PREFIX/lib/libpetsc.a" || { echo "ERROR: libpetsc.a not installed"; exit 1; }

# --- guard: prove the optimisation flags actually reached the compiler -----
# PETSc silently downgrades to "-g -O" when COPTFLAGS is missing, and the only symptom is
# a slower release. Fail the build rather than ship that again.
vars="$PREFIX/lib/petsc/conf/petscvariables"
ccflags="$(grep '^CC_FLAGS' "$vars" 2>/dev/null || true)"
echo "=== $ccflags ==="
case "$ccflags" in
  *-O3*) ;;
  *) echo "ERROR: PETSc was not built optimised -- CC_FLAGS lacks -O3."
     echo "       Expected COPTFLAGS='$PETSC_OPTFLAGS' to reach the compiler."
     exit 1 ;;
esac
# Redistributed binaries must not be tuned to the build host.
case "$ccflags" in
  *-march=native*) echo "ERROR: -march=native in a redistributable PETSc build."; exit 1 ;;
esac

echo "=== PETSc installed: $(ls -la "$PREFIX/lib/libpetsc.a") ==="
