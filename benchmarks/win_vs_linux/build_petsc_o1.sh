#!/bin/bash
# Build a second PETSc 3.24.5 that mirrors the *Windows* build's flags, so the effect of PETSc's
# optimisation level can be measured on Linux directly.
#
# The Windows install reports  CC_FLAGS = ... -g -O  (i.e. -O1, generic arch) because
# --with-debugging=0 without an explicit COPTFLAGS makes PETSc fall back to plain -O.
# Everything else is copied verbatim from
#   petsc/src/petsc-3.24.5/arch-linux-c-opt/lib/petsc/conf/reconfigure-arch-linux-c-opt.py
# with only the three *OPTFLAGS lines dropped.
#
# The soname (libpetsc.so.3.24) is identical to the -O3 install, so PICLas does NOT need
# relinking -- prepend this prefix's lib/ to LD_LIBRARY_PATH and the same piclas binary picks
# it up. Same source, same config, same ABI: a genuine one-variable swap.
set -e
source /home/alopp/benchmarks/win_vs_linux/bench_env.sh

SRC=/home/alopp/petsc/src/petsc-3.24.5
PREFIX=/home/alopp/petsc/3.24.5-O1
ARCH=arch-linux-c-o1

cd $SRC
# bench_env.sh points PETSC_DIR at the *install* prefix; configure insists it be the source tree.
export PETSC_DIR=$SRC
unset PETSC_ARCH
python3 ./configure \
  --prefix=$PREFIX \
  --with-bison=0 \
  --with-cc=mpicc \
  --with-cxx=mpicxx \
  --with-debugging=0 \
  --with-fc=mpif90 \
  --with-mpi-f90module-visibility=0 \
  --with-mpiexec=mpirun \
  --with-shared-libraries=1 \
  PETSC_ARCH=$ARCH

make PETSC_DIR=$SRC PETSC_ARCH=$ARCH -j"$(nproc)" all
make PETSC_DIR=$SRC PETSC_ARCH=$ARCH install

echo "=== resulting flags (compare to Windows '-g -O') ==="
grep '^CC_FLAGS' $PREFIX/lib/petsc/conf/petscvariables
