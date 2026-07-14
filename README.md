<img src="docs/logo.png" width="582" height="287">

# piclas-win — an unofficial Windows port of PICLas

> **This is an unofficial, community Windows port of [PICLas](https://github.com/piclas-framework/piclas).**
> It is **not** produced, endorsed, or supported by the official PICLas developers
> (Institute of Space Systems, University of Stuttgart / boltzplatz — numerical plasma dynamics GmbH).
> For the official, upstream code please go to **https://github.com/piclas-framework/piclas**.

`piclas-win` builds and runs the PICLas PIC-DSMC plasma/particle solver natively on
**Windows 10/11** using the MSYS2 UCRT64 toolchain and Microsoft MPI, without WSL, Cygwin, or a
Linux virtual machine. The native executable is named **`piclas-win.exe`** to distinguish it from
the official upstream `piclas` binary.

---

## License and modification notice

`piclas-win` is based on PICLas, which is licensed under the
[GNU General Public License v3.0](http://fsf.org/). This port is likewise distributed under the
**GNU General Public License v3.0**. The full license text is in [LICENCE.md](LICENCE.md) and the
list of original contributors in [CONTRIBUTORS.md](CONTRIBUTORS.md).

In accordance with **section 5(a) of the GPLv3** ("the work must carry prominent notices stating
that you modified it, and giving a relevant date"), we note:

* **This is a modified version of PICLas.** The original work is © 2010–2018 Prof. Claus-Dieter Munz
  and Prof. Stefanos Fasoulas and the PICLas contributors, and remains available unmodified at
  https://github.com/piclas-framework/piclas.
* The Windows port (`piclas-win`) was created and modified during **2026** by Andreas Lopp
  (see [CONTRIBUTORS.md](CONTRIBUTORS.md)). The nature of the changes is summarised below and tracked
  in the commit history of this repository.
* The complete corresponding source for these modifications is this repository itself.
* The startup banner of the program identifies the running binary as
  `piclas-win 2.0 -- unofficial Windows port, based on PICLas 4.2.0`.

PICLas is a scientific project. If you use it (including this port) for publications or
presentations in science, please support the original project by citing the publications listed in
[REFERENCE.md](REFERENCE.md).

### What was changed for the Windows port

The port keeps PICLas' physics and numerics intact and focuses on platform portability. The main
categories of change are:

* **Build system:** MSYS2 UCRT64 / MinGW-w64 GFortran toolchain, CMake presets for Windows, MS-MPI
  detection and link ordering, serial HDF5 detection, optional CUDA (GPU) integration.
* **Serial-HDF5 I/O:** PICLas on Windows links against the serial HDF5 package. Parallel output is
  funneled through `GatheredWriteArray`/`DistributedWriteArray` so that only the MPI root opens the
  HDF5 files.
* **MS-MPI compatibility:** several `MPI_IN_PLACE` reductions and gathers were rewritten with
  explicit send buffers, because MS-MPI handles `MPI_IN_PLACE` on small/single-member communicators
  differently from Open MPI / MPICH.
* **Windows runtime helpers:** Win32 command-line wildcard expansion and a physical-memory query
  used for a memory-based particle-number cap (to avoid hard OS freezes on runaway particle growth).
* **Optional GPU acceleration:** a CUDA particle-push layer loaded via an explicit `LoadLibrary`
  loader to avoid the Windows DLL loader-lock deadlock.

A detailed change log lives in [`windows-tools/`](windows-tools/) (see
`piclas_windows_guide_summary.md`).

---

## Welcome

PICLas is a parallel, three-dimensional, high-order **Particle-in-Cell (PIC)** and
**Direct Simulation Monte Carlo (DSMC)** solver and a flexible particle-based plasma simulation
suite. It is used for, among other things, rarefied gas flows, electric propulsion, reactive flows,
and plasma simulations.

This repository lets you build and run that solver natively on Windows. It is intended for Windows
users who want to experiment with PICLas without a Linux environment. For production science work,
and for the authoritative feature set and documentation, please refer to the upstream project.

---

## Documentation and Installation

The physics, parameters, and usage of PICLas are documented in the official
[PICLas User Guide](https://piclas.readthedocs.io/). Everything about *how to set up a simulation*
(parameter files, mesh generation, post-processing) applies equally to this port — only the build
procedure and the executable name (`piclas-win.exe`) differ.

### Dependencies (Windows port)

| Component | Purpose | Notes |
|-----------|---------|-------|
| [MSYS2](https://www.msys2.org/) (UCRT64 environment) | Build environment / shell | Not Cygwin, not WSL |
| MinGW-w64 **GCC / GFortran 15.x** | Fortran/C/C++ compilers | via `mingw-w64-ucrt-x86_64-gcc`, `-gcc-fortran` |
| [CMake](https://www.cmake.org) ≥ 3.10 (4.2.x tested) + [Ninja](https://ninja-build.org/) | Configure / build | |
| [Microsoft MPI (MS-MPI) 10.1](https://learn.microsoft.com/message-passing-interface/microsoft-mpi) | Parallel execution | runtime + `mingw-w64-ucrt-x86_64-msmpi` |
| [HDF5](https://www.hdfgroup.org/) 2.1.0 (**serial**) | I/O of state/mesh files | MSYS2 package is serial-only |
| [LAPACK](http://www.netlib.org/lapack/) / OpenBLAS | Dense linear algebra | via MSYS2 |
| [PETSc](https://petsc.org/) 3.24.5 *(optional)* | HDG / implicit solvers, FPC | MSYS2 build is **sequential** (MPI=1 only) |
| [CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) 12.x + VS Build Tools 2022 *(optional)* | GPU particle push | GPU builds only |
| [hopr-win](https://github.com/HallGrossaxt/hopr-win) | Mesh pre-processor | Windows port of [HOPR](https://github.com/hopr-framework/hopr); needed for most test cases |
| [reggie2.0-win](https://github.com/HallGrossaxt/reggie2.0-win) | Regression-test runner | Windows port of [reggie2.0](https://github.com/piclas-framework/reggie2.0); see below |
| [Python](https://www.python.org/) 3.x | reggie + helper tooling | |

> **Key constraints on Windows:**
> * **MPI + PETSc cannot be combined** — the MSYS2 PETSc package is sequential, so PETSc-enabled
>   builds run at MPI = 1 only. Standard HDG Poisson still runs in parallel via PICLas' internal CG
>   solver (PETSc off); only the floating-conductor / FPC model strictly requires PETSc.
> * **HDF5 is serial** (`USE_MPI_HDF5=0`); set `HDF5_USE_FILE_LOCKING=FALSE` for MPI runs.

### Installing the build environment

1. Install [MSYS2](https://www.msys2.org/) and open the **UCRT64** shell.
2. Install the toolchain and libraries:
   ```bash
   pacman -S --needed \
     mingw-w64-ucrt-x86_64-gcc \
     mingw-w64-ucrt-x86_64-gcc-fortran \
     mingw-w64-ucrt-x86_64-cmake \
     mingw-w64-ucrt-x86_64-ninja \
     mingw-w64-ucrt-x86_64-hdf5 \
     mingw-w64-ucrt-x86_64-openblas \
     mingw-w64-ucrt-x86_64-msmpi \
     git python
   ```
3. Install the **Microsoft MPI runtime** (`msmpisetup.exe`) from Microsoft so that `mpiexec.exe`
   is available (typically `C:\Program Files\Microsoft MPI\Bin\mpiexec.exe`).
4. *(Optional, GPU builds only)* Install the CUDA Toolkit 12.x and Visual Studio Build Tools 2022.

### Building piclas-win

From the **UCRT64** shell, in the repository root:

```bash
export TEMP=/tmp && export TMP=/tmp        # system TEMP may be read-only

# Configure + build using one of the provided CMake presets:
cmake --preset windows-ucrt64-mpi          # MS-MPI build (maxwell/DSMC)
cmake --build --preset windows-ucrt64-mpi
```

The resulting executable is **`build-<preset>/bin/piclas-win.exe`** (plus `libpiclas.dll`).

Available presets:

| Preset | Physics | GPU |
|--------|---------|-----|
| `windows-ucrt64`         | Base (serial)        | No  |
| `windows-ucrt64-mpi`     | + MS-MPI             | No  |
| `windows-ucrt64-poisson` | Poisson + RK3        | No  |
| `windows-ucrt64-debug`   | Debug build          | No  |
| `windows-ucrt64-gpu`     | + CUDA (sm_86)       | Yes |
| `windows-ucrt64-superB`  | maxwell + RK4 + POSTI| No  |

### Running

```powershell
$env:HDF5_USE_FILE_LOCKING = "FALSE"
# serial:
.\bin\piclas-win.exe parameter.ini [DSMC.ini]
# parallel (4 ranks):
& "C:\Program Files\Microsoft MPI\Bin\mpiexec.exe" -n 4 .\bin\piclas-win.exe parameter.ini [DSMC.ini]
```

Meshes are generated with the Windows HOPR port (`hopr-win`).

---

## Regression Testing (Windows / reggie2.0 port)

Continuous-integration regression testing uses the **[reggie2.0-win](https://github.com/HallGrossaxt/reggie2.0-win)
test runner** (the Windows port of [reggie2.0](https://github.com/piclas-framework/reggie2.0)), driving the test
definitions under [`regressioncheck/`](regressioncheck/). The reggie port adds Windows fixes such as
an `.exe` binary-lookup fallback, thread-based pipe reading (replacing POSIX `select`), and correct
`excludeBuild.ini` handling in external-binary mode.

Example run (PowerShell, UCRT64 on `PATH`):

```powershell
$env:HDF5_USE_FILE_LOCKING = "FALSE"
$env:PATH = "C:\msys64\ucrt64\bin;C:\msys64\usr\bin;" + $env:PATH
$reggie = "C:\path\to\reggie2.0-venv\bin\reggie.exe"
$exe    = ".\build-windows-ucrt64-mpi\bin\piclas-win.exe"
$mpi    = "C:\Program Files\Microsoft MPI\Bin\mpiexec.exe"
& $reggie regressioncheck\NIG_DSMC -e $exe -m $mpi -c -s -l 4
```

### Status (NIG suite, May 2026)

Of the 35 `NIG_` regression suites, **14 pass fully clean** (0 errors of any kind) and **17 more run
to completion** (reggie exit 0) with residual analyze differences that are mostly Windows-vs-Linux
floating-point reference mismatches; 3 are skipped. Verified working areas include the serial and
MPI core, the Landau-damping PIC tutorial (MPI×4), DSMC, the superB pre-processor, and the optional
GPU particle push. Remaining open items (notably a flaky high-MPI segfault after load balance,
"Bug G") are documented in [`windows-tools/piclas_windows_guide_summary.md`](windows-tools/piclas_windows_guide_summary.md).

Because Monte-Carlo/DSMC results are statistical and platform floating-point ordering differs
between Windows and Linux, the port validates statistical invariants (conservation laws,
distributions, mean fluxes) rather than bit-for-bit agreement with Linux-generated reference files.

---

## Used libraries

`piclas-win` uses several external libraries as well as auxiliary functions from open source
projects, including:

* [hopr-win](https://github.com/HallGrossaxt/hopr-win) — Windows port of [HOPR (High Order Preprocessor)](https://github.com/hopr-framework/hopr)
* [PyHOPE](https://github.com/hopr-framework/PyHOPE) — Python High Order Preprocessor (upstream's mesh generator for tutorials/regression tests since PICLas 4.2.0)
* [reggie2.0-win](https://github.com/HallGrossaxt/reggie2.0-win) — Windows port of the [reggie2.0](https://github.com/piclas-framework/reggie2.0) regression-test runner
* [cmake](https://www.cmake.org) and [Ninja](https://ninja-build.org/)
* [LAPACK](http://www.netlib.org/lapack/) / [OpenBLAS](https://www.openblas.net/)
* [MS-MPI](https://learn.microsoft.com/message-passing-interface/microsoft-mpi) (Microsoft MPI)
* [HDF5](https://www.hdfgroup.org/)
* [PETSc](https://petsc.org/) *(optional)*
* [CUDA](https://developer.nvidia.com/cuda-toolkit) *(optional, GPU builds)*
* [MSYS2 / MinGW-w64](https://www.msys2.org/) toolchain (GCC/GFortran)

---

## Disclaimer

This is an unofficial, community Windows port provided **"as is", without warranty of any kind** and
**without any guarantee of support**. It is distributed under the GNU General Public License v3.0; see
**sections 15 and 16** of [LICENCE.md](LICENCE.md) for the full disclaimer of warranty and limitation
of liability. Use at your own risk. The original PICLas authors and contributors are **not**
responsible for this port.

## Support, bugs, and questions

* **For this Windows port** (build problems, Windows-specific bugs): please open an issue in *this*
  repository.
* **For PICLas itself** (physics, features, the solver, the User Guide): please use the
  [official PICLas repository](https://github.com/piclas-framework/piclas) and its channels. The
  official developers can be reached through:
  * [Numerical Modelling and Simulation Group, Institute of Space Systems, University of Stuttgart](https://www.irs.uni-stuttgart.de/en/research/space-transport-technology/numerical-modeling-and-simulations/)
  * [boltzplatz — numerical plasma dynamics GmbH](https://boltzplatz.eu)

Please do **not** direct questions about this unofficial port to the official PICLas developers.
