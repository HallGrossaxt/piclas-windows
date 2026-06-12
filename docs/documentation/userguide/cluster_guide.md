# Cluster Guidelines (not applicable to the Windows port)

The **piclas-win** Windows port targets **Windows 10/11 desktops/workstations** with the MSYS2
UCRT64 toolchain and Microsoft MPI. It is **not** intended for, or tested on, Linux HPC clusters.

All cluster-specific guidance — HLRS/Hawk module environments, SSH proxy-jump/tunneling for cloning,
`module load` toolchains, PETSc/HDF5 cluster builds, batch submission — is **Linux-only** and lives
in the upstream original:

> <https://piclas.readthedocs.io/en/latest/userguide/cluster_guide.html>

For running piclas-win on Windows, see [Installation](installation.md).
