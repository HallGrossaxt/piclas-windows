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
# ---------------------------------------------------------------------------
set -euo pipefail

PETSC_VERSION="${PETSC_VERSION:-3.24.5}"
PREFIX="${PETSC_PREFIX:?set PETSC_PREFIX (MSYS path to install dir)}"
SRC="${PETSC_SRC:-$PWD/petsc-src}"
MINGW="${MINGW_PREFIX:?MINGW_PREFIX not set (run in the MSYS2 UCRT64 shell)}"

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
  --with-debugging=0

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
echo "=== PETSc installed: $(ls -la "$PREFIX/lib/libpetsc.a") ==="
