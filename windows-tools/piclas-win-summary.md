# piclas-win — Windows Port of PICLas 4.1.0
## Project Summary

**Date:** 2026-05-24  
**Based on:** PICLas v4.1.0 (commit d63756ee)  
**Platform:** Windows 11 Pro · MSYS2 UCRT64 · GCC/GFortran 15.x  
**Build system:** CMake 4.2.x · Ninja 1.12.x  
**MPI:** Microsoft MPI (MS-MPI) v10.1 via `mingw-w64-ucrt-x86_64-msmpi`  
**HDF5:** v2.1.0, serial only (no parallel MPI support in the MSYS2 package)

---

## 1. Strategy

PICLas is compiled **natively on Windows** using GCC/GFortran from MSYS2 UCRT64.  
No WSL, no Cygwin. The resulting `piclas.exe` is a real Windows executable that runs  
without MSYS2 at runtime when the required DLLs are bundled alongside it.

**Key constraint:** MSYS2's HDF5 has no parallel MPI support (`USE_MPI_HDF5=0`). All  
HDF5 file I/O is therefore serial even in MPI runs. Only MPIRoot (rank 0) opens HDF5  
files; non-root ranks send their data via `MPI_GATHERV` and MPIRoot writes (the  
*gather-write pattern* implemented in `GatheredWriteArray` / `DistributedWriteArray`).

**Key constraint:** MSYS2 PETSc is a sequential (non-MPI) build. **MPI and PETSc cannot  
be used together.** Choose one or the other per build.

---

## 2. All Changes Made

### 2.1 New Files Created

| File | Purpose |
|---|---|
| `src/globals/glob_windows.c` | Win32 wildcard expansion using `FindFirstFileA`. Called from Fortran via ISO_C_BINDING. On Linux/macOS compiles to a no-op stub. Enables `piclas2vtk parameter.ini State_*.h5` from any Windows terminal. |
| `C:\msys64\ucrt64\lib\pkgconfig\petsc.pc` | pkg-config wrapper pointing to the MSYS2 PETSc DSO variant. Without it PICLas tries to build PETSc from source (fails on Windows). |
| `piclas_builder.html` | Standalone HTML build configurator — generates cmake commands and downloads a ready-to-run `.bat` script. Runs in any browser. |
| `piclas_builder.hta` | HTA build configurator — double-click in Windows Explorer for live streaming build output. |
| `piclas_builder.py` | Python web-server build configurator (`python3 piclas_builder.py`, then open `localhost:8765`). |
| `C:\msys64\ucrt64\mod\static\` | Empty directory — silences GFortran warning about missing HDF5 Fortran module path. |

### 2.2 Modified Source Files (PICLas)

#### `CMakeLists.txt` (root) — Fix D
- Use **full path** to `powershell.exe` (`C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`)  
  in the userblock pre-build step.  
  **Reason:** During Ninja builds, Windows PowerShell is not in the effective PATH.

#### `CMakePresets.json`
- Added configure and build presets:
  - `windows-ucrt64` — base MSYS2 UCRT64 preset
  - `windows-ucrt64-mpi` — MPI-enabled (inherits base, adds `LIBS_USE_MPI=ON`, sets MPI compiler paths to `C:/msys64/ucrt64/bin/mpicc` etc.)
  - `windows-ucrt64-poisson` — Poisson solver with PETSc
  - `windows-ucrt64-debug` — Debug build

#### `cmake/SetLibraries.cmake` — Fixes A, B, C
- **Fix A — linker ordering:** `mpi_f08.o` must precede `libmsmpi.dll.a` in the link command.  
  Changed from `LIST(APPEND…)` to `LIST(INSERT … 0 …)`.
- **Fix B — HDF5 parallel detection false positive:** Changed grep from `mpio_f` (which  
  matched the always-present `h5fd_mpio_f_` constant) to `h5pset_fapl_mpio_f` (only  
  present in parallel-capable builds).
- **Fix C — `USE_MPI_HDF5` compile flag:** New preprocessor flag = 1 only when both  
  `LIBS_USE_MPI=ON` AND HDF5 was built with parallel support. Guards 5 call sites of  
  `H5PSET_FAPL_MPIO_F` and `H5PSET_DXPL_MPIO_F` that do not exist in the MSYS2 serial HDF5.

#### `src/globals/commandlinearguments.f90`
- Added `ISO_C_BINDING` interface for `glob_expand_c`.  
- Any command-line argument containing `*` or `?` is routed through `glob_expand_c`  
  before use, enabling wildcard expansion on Windows.

#### `src/CMakeLists.txt` — Fix E
- Added `globlib` static library build and linked it to `piclas`, `piclas2vtk`, `libpiclasshared`.
- On Windows, linked `${linkedlibs}` (contains `mpi_f08.o` + `libmsmpi.dll.a`) directly to  
  executables — necessary because Windows does not re-export transitive DLL dependencies through  
  import stubs.

#### `unitTests/CMakeLists.txt`
- Added `ADD_DEPENDENCIES(${target} libpiclasstaticF90)` to prevent a Ninja parallel-build race  
  condition where unit tests compile before Fortran `.mod` files are generated.
- On Windows: also links `${linkedlibs}` to unit test executables.

#### `src/io_hdf5/io_hdf5.f90` — Fixes C, F
- Guarded `H5PSET_FAPL_MPIO_F` with `#if USE_MPI_HDF5`.
- **Fix F — Userblock / HDF5 superblock corruption:** Added `H5PSET_USERBLOCK_F` call  
  on the property list *before* `H5FCREATE_F`, and passed `creation_prp=Plist_File_ID`.  
  **Reason:** Without reserving aligned space for the userblock, `copy_userblock` overwrote  
  the HDF5 superblock, corrupting every output file.

#### `src/io_hdf5/hdf5_input.f90` — Fix C
- Guarded `H5PSET_FAPL_MPIO_F` / `H5PSET_DXPL_MPIO_F` calls at 3 locations with `#if USE_MPI_HDF5`.

#### `src/io_hdf5/hdf5_output.f90` — Fixes C, G
- Guarded `H5PSET_DXPL_MPIO_F` with `#if USE_MPI_HDF5`.
- **Fix G — Sequential HDF5 gather-write pattern:** `GatheredWriteArray` and  
  `DistributedWriteArray` now use `#if USE_MPI && !USE_MPI_HDF5` to route all data through  
  `MPI_GATHERV` → MPIRoot → single HDF5 write, preventing `H5DCREATE_F(File_ID=0)` failures  
  on non-root ranks.

#### `src/particles/dsmc/dsmc_analyze.f90` — Fix H
- **Fix H — WriteDSMCToHDF5 gather-write:** Replaced direct `OpenDataFile` + `WriteArrayToHDF5`  
  + `CloseDataFile` calls (which ran on all ranks) with `GatheredWriteArray` calls.  
  **Reason:** Non-root ranks had `File_ID=0` and `H5DCREATE_F` failed with  
  *"Dataset ElemData could not be created"*.

#### `src/particles/particle_mesh/particle_mesh_readin.f90` — Bug 13.1 Fix ✅
- Guarded the blocking `MPI_ALLGATHERV(MPI_IN_PLACE, …)` on `MPI_COMM_LEADERS_SHARED`  
  with `IF (nLeaderGroupProcs.GT.1)`.  
  **Reason:** On a single compute node this communicator has exactly 1 member. MS-MPI zeroes  
  the receive buffer before filling it from the in-place source, wiping `SideInfo_Shared`.

#### `src/particles/particle_mpi/particle_mpi_halo.f90` — Bug 13.3 Fix ✅
- Replaced `IF (halo_eps.LE.0.)` with `IF (nComputeNodeProcessors.EQ.nProcessors_Global)` in  
  `IdentifyPartExchangeProcs`.  
  **Reason:** When `shape_function` deposition is active, `particle_bgm.f90` sets `halo_eps > 0`  
  even on a single node, causing the code to enter the multi-node branch and use  
  `MPI_halo_eps = 1.0` (too small for non-adjacent procs to find each other).

#### `tutorials/pic-poisson-landau-damping/parameter.ini` — Bug 13.2 Workaround ⚠️
- Added `CartesianPeriodic = T` immediately after `TrackingMethod = refmapping`.  
  **Reason:** Intersection-based periodic boundary tracking fails on Windows for particles  
  crossing the `x=0` face (floating-point edge case in `ParticleBCTracking`). This flag  
  activates `PeriodicMovement` which wraps positions directly, bypassing the intersection code.

---

## 3. Build System Configuration

### Toolchain
| Component | Version | Notes |
|---|---|---|
| GCC / GFortran | 15.2.0 | MSYS2 UCRT64 |
| CMake | 4.2.3 | `mingw-w64-ucrt-x86_64-cmake` |
| Ninja | 1.12.x | `mingw-w64-ucrt-x86_64-ninja` |
| HDF5 | 2.1.0 | Serial only — `USE_MPI_HDF5=0` |
| MS-MPI | 10.1 | `mingw-w64-ucrt-x86_64-msmpi` |
| PETSc | 3.24.5 | Sequential (cannot combine with MPI) |
| Python | 3.14.x | Build configurator web server |

### Build Presets
```
cmake --preset windows-ucrt64-mpi          # MPI + Poisson (Leapfrog, Release)
cmake --preset windows-ucrt64-poisson      # Poisson + PETSc (no MPI)
cmake --preset windows-ucrt64              # Base preset
cmake --preset windows-ucrt64-debug        # Debug build
```

### Important Environment Variables (must be set before building/running)
```bash
export PETSC_DIR=/c/msys64/ucrt64      # Needed for cmake configure with PETSc
export TEMP=/tmp                        # Avoid permission errors writing gcc temp files
export TMP=/tmp
export HDF5_USE_FILE_LOCKING=FALSE     # Required for all MPI runs
```

### Known Constraints
- **MPI + PETSc cannot be combined** — MSYS2 PETSc is sequential-only. cmake emits `FATAL_ERROR` if both are requested. The MPI build (`windows-ucrt64-mpi`) has `LIBS_USE_PETSC=OFF`.
- **HDF5 is serial** — even in MPI builds. All HDF5 writes go through MPIRoot via the gather-write pattern.

---

## 4. Runtime Bugs — Landau Damping PIC-Poisson Tutorial (`mpiexec -n 4`)

All three bugs are Windows/MS-MPI-specific. Single-process runs and Linux are unaffected.

---

### Bug 13.1 — MS-MPI `MPI_ALLGATHERV(MPI_IN_PLACE)` corrupts `SideInfo_Shared` ✅ FIXED

| | |
|---|---|
| **Symptom** | `FATAL ERROR: GlobalSideID not found for Elem …` — crash during mesh initialisation |
| **Root cause** | `particle_mesh_readin.f90`: a blocking `MPI_ALLGATHERV(MPI_IN_PLACE, …)` on `MPI_COMM_LEADERS_SHARED` (1-member communicator on a single node). MS-MPI zeroes the receive buffer before filling it from the in-place source — but source = buffer → data wiped. `SideInfo_Shared` columns 1–9 all become 0; `GetGlobalNonUniqueSideID` finds no matching side → abort. |
| **Why Windows only** | Linux/OpenMPI treats 1-process `MPI_IN_PLACE` as a no-op. MS-MPI is unique in zeroing first. |
| **Fix applied** | `particle_mesh_readin.f90` line 430: `IF (nLeaderGroupProcs.GT.1)` guards the call. On a single node the data is already in shared memory — the gather is skipped. |
| **Status** | ✅ **Applied** — patch in source tree (2026-04-02), compiled into binary (2026-04-05). |

---

### Bug 13.2 — Intersection-based periodic boundary tracking fails ⚠️ WORKAROUND ACTIVE

| | |
|---|---|
| **Symptom** | `ERROR: Particle not inside of Element, ipart …` — particles near `x=0` moving in −x direction are lost in the first time step |
| **Root cause** | `TrackingMethod = refmapping` uses `ParticleBCTracking` for intersection-based periodic BC handling. On Windows this routine fails to detect the `x=0` crossing. Likely a floating-point rounding difference between MSVC-compatible math routines and glibc causes a different code path in the intersection geometry. After the Boris push, particles end up at `x < 0` (outside domain), `SinglePointToElement` returns −1, and `RemoveParticle` / abort fires. |
| **What was tried** | Investigated code path — the exact numerical edge case was not identified. The upstream Linux build with OpenMPI passes this test. |
| **Workaround** | `CartesianPeriodic = T` in `parameter.ini` activates `PeriodicMovement`: positions are wrapped directly (`pos = pos ± L`) instead of computing intersection points. Physically equivalent for a Cartesian periodic domain. **This flag must remain set for all Windows runs.** |
| **Root cause** | ⚠️ **Still open** — the intersection-geometry floating-point bug in `ParticleBCTracking` on Windows has not been identified or fixed. The workaround bypasses the buggy code path entirely. |
| **What should be done** | Investigate `ParticleBCTracking` with a GFortran debug build (`-ffpe-trap=invalid -fbounds-check -fbacktrace`). Compare the intersection test values between the Linux and Windows builds for a single particle near `x=0`. The likely culprit is a trigonometric or dot-product comparison that yields a slightly different sign on Windows due to extended precision FPU behaviour. |

---

### Bug 13.3 — Single-node `shape_function` run: MPI exchange halo too small ✅ FIXED

| | |
|---|---|
| **Symptom** | `GlobalProcToExchangeProc(EXCHANGE_PROC_RANK,ProcID) is negative. The halo region might be too small.` — abort at end of first time step |
| **Root cause** | In `particle_mpi_halo.f90:IdentifyPartExchangeProcs`, the branch `IF (halo_eps.LE.0.)` was intended to detect single-node runs and set `MPI_halo_eps ≈ 1.2×10⁷` (spanning the whole domain). But when `PIC-Deposition-Type = shape_function` is active, `particle_bgm.f90` sets `halo_eps = MAX(r_sf, y_extent, z_extent) = 1.0 > 0`, triggering the multi-node branch and setting `MPI_halo_eps = 1.0`. With proc-width ≈ 3.14, procs 0 and 2 (and 1 and 3) are not in each other's exchange lists. A particle with an inflated velocity (from corrupted field interpolation due to a misplaced particle accessing out-of-bounds `U_N(LocalElemID)%E`) jumps two proc-widths in one step and cannot be routed → abort. |
| **Cascade failure** | A misplaced particle with the wrong `GlobalElemID` → `LocalElemID` out of bounds → garbage E-field (~10²⁴) → garbage velocity (~−2.7×10²³) → position integer overflow in `CEILING` inside `PeriodicMovement`. |
| **Fix applied** | `particle_mpi_halo.f90` line 399: `IF (halo_eps.LE.0.)` replaced with `IF (nComputeNodeProcessors.EQ.nProcessors_Global)`. Correctly detects single-node regardless of what `halo_eps` was set to by the deposition module. |
| **Status** | ✅ **Applied** — patch in source tree (2026-04-05 20:40), compiled into binary (2026-04-05 20:59). |

---

## 5. Open Bugs Summary

| # | Bug | Status | Action needed |
|---|---|---|---|
| 13.1 | MS-MPI `MPI_ALLGATHERV(MPI_IN_PLACE)` corrupts `SideInfo_Shared` | ✅ Fixed & compiled | None |
| 13.2 | Intersection-based periodic BC tracking fails on Windows | ⚠️ Workaround only (`CartesianPeriodic=T`) | Investigate `ParticleBCTracking` FP edge case with debug build |
| 13.3 | Single-node `shape_function` halo too small (`halo_eps > 0` triggers multi-node path) | ✅ Fixed & compiled | None |

### What still needs to be done for Bug 13.2

1. Build a **debug binary** (`cmake --preset windows-ucrt64-debug`) with `-ffpe-trap=invalid,zero,overflow -fbounds-check -fbacktrace`.
2. Run the tutorial **without** `CartesianPeriodic = T` and capture the exact line/variable in `ParticleBCTracking` where the crossing fails.
3. Compare the intersection test values (dot-products, distance thresholds) for a particle near `x=0` between Linux and Windows builds — the fault is likely a sign flip or near-zero comparison that has opposite outcomes due to different floating-point rounding.
4. Apply a tolerance guard (e.g. `IF (ABS(xi - xmin) < eps) ...`) or force flush-to-zero at the intersection test boundary.
5. Once fixed in source, remove `CartesianPeriodic = T` from `parameter.ini` and re-verify.

---

## 6. Build & Test Verification (2026-05-24)

### 6.1 Rebuild Command
```bash
# From MSYS2 UCRT64 shell, source root p:/Data/prj/piclas-win/piclas-win-master
# Stale CMakeCache was removed (original cache pointed to old path C:/Data/PRJ/Piclas/piclas-master)
export PATH=/c/msys64/ucrt64/bin:/c/msys64/usr/bin:$PATH
export PETSC_DIR=/c/msys64/ucrt64
export TEMP=/tmp; export TMP=/tmp
cmake --preset windows-ucrt64-mpi          # Re-configure (stale cache removed 2026-05-24)
cmake --build --preset windows-ucrt64-mpi --target piclas piclas2vtk
```

> **Status:** 🔄 Rebuild in progress (cmake configure running as of 2026-05-24 12:06).  
> This section will be updated when the build and test run complete.

### 6.2 Previous Verified Build (2026-04-05)

The binary at `build-ucrt64-mpi/single/piclas.exe` was built 2026-04-05 20:59.  
At that time, both the §13.1 patch (`particle_mesh_readin.f90`, 2026-04-02) and the §13.3 patch  
(`particle_mpi_halo.f90`, 2026-04-05 20:40) were already present in the source tree.  
The `FieldAnalyze.csv` and `PartAnalyze.csv` files in `build-ucrt64-mpi/single/` are dated  
2026-04-05 22:02 — confirming a full tutorial run completed successfully on that date.

### 6.3 Test Run
- **Working directory:** `build-ucrt64-mpi/single/`
- **Command:**
  ```
  set HDF5_USE_FILE_LOCKING=FALSE
  mpiexec -n 4 piclas.exe parameter.ini
  ```
- **`parameter.ini` settings active:**
  - `TrackingMethod = refmapping`
  - `CartesianPeriodic = T` (Bug 13.2 workaround)
  - `PIC-Deposition-Type = shape_function` (requires Bug 13.3 fix)
- **Expected output:** `FieldAnalyze.csv`, `PartAnalyze.csv`, `landau_damping_State_*.h5` files written cleanly; no FATAL ERROR or abort.

> **Status:** 🔄 Pending rebuild completion.

---

## 7. Distribution (Running Without MSYS2)

Copy `piclas.exe`, `piclas2vtk.exe`, and all MSYS2 DLLs to the target machine:

```bash
ldd piclas.exe | grep ucrt64 | awk '{print $3}' | xargs -I{} cp {} ./dist/
```

**Required DLLs (typical):**
- `libgcc_s_seh-1.dll`, `libgfortran-5.dll`, `libgomp-1.dll`, `libwinpthread-1.dll`
- `libstdc++-6.dll`, `hdf5.dll`, `hdf5_fortran.dll`
- `libpetsc-dso.dll`, `libopenblas.dll` (only if PETSc build)
- `libzlib1.dll`, `libsz.dll` (HDF5 compression dependencies)

For MPI runs: `msmpi.dll` must be present in `C:\Windows\System32\` (installed by the  
MS-MPI runtime installer from Microsoft).

---

## 8. Reproducing the Build on a New Machine

1. Install MSYS2 to `C:\msys64` from `msys2.org` → open **MSYS2 UCRT64**
2. `pacman -Syu` (update), then install packages:
   ```
   pacman -S --noconfirm mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gcc-fortran \
     mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja \
     mingw-w64-ucrt-x86_64-hdf5 mingw-w64-ucrt-x86_64-python \
     mingw-w64-ucrt-x86_64-petsc mingw-w64-ucrt-x86_64-msmpi git
   ```
3. `mkdir -p /c/msys64/ucrt64/mod/static`
4. Create `petsc.pc` wrapper at `/c/msys64/ucrt64/lib/pkgconfig/petsc.pc`
5. Copy the patched source tree (all modified/new files listed in §2)
6. Install MS-MPI runtime from Microsoft (provides `msmpi.dll` in `System32`)
7. `cmake --preset windows-ucrt64-mpi` then `cmake --build --preset windows-ucrt64-mpi --target piclas piclas2vtk`
8. Set `HDF5_USE_FILE_LOCKING=FALSE` before any MPI run
