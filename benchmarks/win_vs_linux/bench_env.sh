# Toolchain for the win-vs-linux PICLas benchmark (GCC 11.2 + OpenMPI 4.1.1 + parallel HDF5 1.12.1).
# Mirrors piclas_old/bugG_env.sh; adds PETSc + reggie venv so all builds/runs share one stack.
export PATH=/home/alopp/hdf5/1.12.1/bin:/home/alopp/openmpi/4.1.1/bin:/home/alopp/gcc/11.2.0/bin:$PATH
export LD_LIBRARY_PATH=/home/alopp/hdf5/1.12.1/lib:/home/alopp/openmpi/4.1.1/lib:/home/alopp/petsc/3.24.5/lib:/usr/lib/x86_64-linux-gnu:/home/alopp/gcc/11.2.0/lib64
export OPAL_PREFIX=/home/alopp/openmpi/4.1.1
export MPI_DIR=/home/alopp/openmpi/4.1.1
export HDF5_DIR=/home/alopp/hdf5/1.12.1
export HDF5_ROOT=/home/alopp/hdf5/1.12.1
export CC=/home/alopp/gcc/11.2.0/bin/gcc
export CXX=/home/alopp/gcc/11.2.0/bin/g++
export FC=/home/alopp/gcc/11.2.0/bin/gfortran
export OMPI_CC=/home/alopp/gcc/11.2.0/bin/gcc
export OMPI_CXX=/home/alopp/gcc/11.2.0/bin/g++
export OMPI_FC=/home/alopp/gcc/11.2.0/bin/gfortran
# PETSc 3.24.5 (plain: no Hypre/MUMPS) matching the Windows PIC build
export PETSC_DIR=/home/alopp/petsc/3.24.5
# reggie2.0 harness (venv)
export REGGIE=/home/alopp/reggie-venv/bin/reggie
export PICLAS_ROOT=/home/alopp/piclas
