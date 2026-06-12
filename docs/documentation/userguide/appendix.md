# Appendix

## Tested combination (Windows port)

The **piclas-win** Windows port is built and tested with the MSYS2 UCRT64 toolchain. The reference
combination used for the binaries in this repository is:

| Component | Version |
| --- | --- |
| OS | Windows 10 / 11 |
| Environment | MSYS2 UCRT64 |
| Compiler | MinGW-w64 GCC / GFortran 15 |
| CMake | 4.2.x |
| Ninja | current MSYS2 package |
| MPI | Microsoft MPI (MS-MPI) |
| HDF5 | 2.1.0 (serial) |
| LAPACK / OpenBLAS | current MSYS2 package |
| PETSc *(optional)* | 3.24.5 (sequential, MPI=1) |
| CUDA *(GPU builds)* | 13.2, NVIDIA RTX 3060 (sm_86), VS Build Tools host compiler |

> The Windows libraries come from MSYS2 packages (`LIBS_BUILD_*=OFF`), so versions track whatever
> MSYS2 currently ships.

For the upstream **Linux/HPC** tested-combination matrix (boltzplatz, Vulcan, Hawk, etc. with
OpenMPI/MPICH builds) and the Linux-specific known-problem notes, see the upstream original:

> <https://piclas.readthedocs.io/en/latest/userguide/appendix.html>
