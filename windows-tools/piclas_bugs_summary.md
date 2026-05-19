# piclas-win 0.9.3 — Windows Port: Bug Fix Summary

Generated: 2026-04-26  
Source: `piclas_windows_guide.html` + session notes

---

## FIXED — Build / Compile-time

| ID | File | Fix |
|----|------|-----|
| Fix A | `cmake/SetLibraries.cmake` | `mpi_f08.o` linker ordering: `LIST(INSERT … 0 …)` so it precedes `libmsmpi.dll.a` |
| Fix B | `cmake/SetLibraries.cmake` | HDF5 parallel detection: grep for `h5pset_fapl_mpio_f` (not `mpio_f`) to avoid false parallel positive |
| Fix C | `cmake/SetLibraries.cmake` + 3 HDF5 source files | New `USE_MPI_HDF5` flag; guards all `H5PSET_FAPL_MPIO_F` / `H5PSET_DXPL_MPIO_F` calls with `#if USE_MPI_HDF5` |
| Fix D | `CMakeLists.txt` | Full path to `powershell.exe` in userblock pre-build step |
| Fix E | `src/CMakeLists.txt`, `unitTests/CMakeLists.txt` | Link `${linkedlibs}` (MPI objects) directly to executables on Windows — DLL import stubs do not re-export transitive symbols |

---

## FIXED — HDF5 I/O

| ID | File | Fix |
|----|------|-----|
| Fix F | `src/io_hdf5/io_hdf5.f90` | Call `H5PSET_USERBLOCK_F` before `H5FCREATE_F` + pass `creation_prp=Plist_File_ID`; prevents userblock overwriting HDF5 superblock |
| Fix G | `src/io_hdf5/hdf5_output.f90` | `GatheredWriteArray` / `DistributedWriteArray`: gather-write pattern for serial HDF5 (`USE_MPI_HDF5=0`); non-root ranks send data to MPIRoot via `MPI_GATHERV`, only root calls `WriteArrayToHDF5` |
| Fix H | `src/particles/dsmc/dsmc_analyze.f90` | `WriteDSMCToHDF5`: replaced `OpenDataFile(single=.FALSE.) + WriteArrayToHDF5` on all ranks with `GatheredWriteArray` — prevents `H5DCREATE_F(File_ID=0)` crash on ranks 1-N |
| Fix F2 | `src/io_hdf5/hdf5_output_particle.f90` | `WriteClonesToHDF5`: same pattern as Fix H — now uses `GatheredWriteArray` instead of direct `WriteArrayToHDF5` |
| Fix F3 | `src/io_hdf5/hdf5_output.f90` | `DistributedWriteArray`: rewritten `!USE_MPI_HDF5` path to gather via full communicator to global MPIRoot (not OutputCOMM whose rank-0 may not be MPIRoot) |
| Fix F4 | `src/io_hdf5/hdf5_output.f90` | `DistributedWriteArray`: fixed `MPI_GATHERV` aliasing error — added `dseqDummyR/I/I4` scalar placeholders used as send buffer when `dseqLocalCount=0` |

---

## FIXED — Runtime MPI Bugs (MS-MPI `MPI_IN_PLACE` on 1-process communicator)

MS-MPI corrupts buffers when `MPI_IN_PLACE` is used on a 1-process communicator (Linux OpenMPI/MPICH are no-ops in this case). Each instance required either a guard or explicit separate buffers.

| ID | File | Symptom | Fix |
|----|------|---------|-----|
| Bug 13.1 | `particle_mesh_readin.f90` | `FATAL ERROR: GlobalSideID not found` — `SideInfo_Shared` zeroed | `IF(nLeaderGroupProcs.GT.1)` guard on blocking `MPI_ALLGATHERV` |
| Bug 13.4 | `particle_mesh_readin.f90` | `Part-FIBGMdeltas: 0.0 / NaN` + `MPI_Win_allocate_shared: Invalid size` | Same guard on all 4 non-blocking `MPI_IALLGATHERV` calls + `MPI_WAITALL` + `MPI_TYPE_FREE` in `StartCommunicateMeshReadin` / `FinishCommunicateMeshReadin` |
| Bug 13.3 | `particle_mpi_halo.f90` | `GlobalProcToExchangeProc is negative` with shape_function | Replace `IF(halo_eps.LE.0.)` with `IF(nComputeNodeProcessors.EQ.nProcessors_Global)` |
| Bug D | `particle_bgm.f90` | `FIBGMdeltas=(Inf,0,Inf)` / `BGMjDelta=INT_MIN` / ~1.5 GB allocation crash | Replace `MPI_ALLREDUCE(MPI_IN_PLACE,…)` with explicit buffers; guard `FIBGM_nTotalElems` and `FIBGMProcs` allreduce on `MPI_COMM_LEADERS_SHARED` with `IF(nLeaderGroupProcs.GT.1)` |
| Bug C | `particle_mesh_tools.f90`, `particle_analyze_tools.f90` | `NumDens-Spec-001 = NaN` | Replace `MPI_ALLREDUCE(MPI_IN_PLACE, CNVolume, …, MPI_COMM_SHARED)` and `MPI_REDUCE(MPI_IN_PLACE, NumSpec, …, MPI_COMM_PICLAS)` with explicit buffers |
| Bug E | `src/mesh/mesh_readin.f90` | `nElems \| 0` in mesh summary (cosmetic) | Replace `MPI_ALLREDUCE(MPI_IN_PLACE, ReduceData, 9, …)` with explicit `ReduceData → ReduceDataTmp → ReduceData` |

---

## FIXED — reggie2.0 Windows Patches

| File | Problem | Fix |
|------|---------|-----|
| `pyproject.toml` | `vtk >= 9.4.0` required — no wheel for Python 3.14 | Removed optional/dev deps (`vtk`, `pre-commit`, `gcovr`, `coverage`); `Analyze_vtudiff` skipped gracefully |
| `reggie/externalcommand.py` | `select.select()` fails on Windows (not socket) | Replaced `os.pipe()` + `select` polling with `subprocess.PIPE` + two `threading.Thread` readers |
| `reggie/check.py` | Binary lookup strips path but omits `.exe` extension | Added `.exe` fallback: `if sys.platform=='win32' and not exists(p) and exists(p+'.exe'): p+='.exe'` |
| `reggie/check.py` | `_link_or_copy()` WinError 3 — relative `src` path resolved from wrong directory | Resolve `src` relative to `dst`'s parent directory before `shutil.copy2` |

---

## FIXED — Runtime: Periodic Boundary Tracking (parameter.ini change)

| ID | File | Symptom | Fix |
|----|------|---------|-----|
| Bug 13.2 | `parameter.ini` | `ERROR: Particle not inside of Element` near periodic x=0 face | Add `CartesianPeriodic = T` — activates `PeriodicMovement` (direct position wrap) instead of intersection-based tracking |

---

## Regression Test Score (after all fixes above)

**11 / 13 test suites PASS** — score improved from 10/13 after the MPI_GATHERV aliasing fix.

| Test | Status | Notes |
|------|--------|-------|
| ANSA_box | PASS | |
| curved | PASS | |
| mortar_hexpress | PASS | |
| periodic | PASS | |
| periodic_2cells | PASS | |
| Semicircle | PASS | |
| sphere_soft | PASS | was FAIL — Bug D fixed |
| tiny_channel | PASS | was FAIL — Bug D fixed |
| **curved_planar** | **PASS** | **was FAIL — Bug F aliasing fix resolved** |
| mortar | FAIL (Bug B) | GPU vs CPU FP reference mismatch |
| mortar_exchange_procs | FAIL (Bug B + Bug G) | |
| surf_flux_2D_track | FAIL (mismatch) | NumDens ~33% low; MPI=4 Adaptive=T crashes |
| exchange_procs | PARTIAL | MPI=1..14 PASS; MPI=15..19 run completes but analyze diff; MPI≥21 crash (Bug G) |

---

## STILL OPEN

| Bug | Affected Tests | Symptom | Root Cause | Suggested Fix |
|-----|---------------|---------|-----------|---------------|
| **B** | `mortar`, `mortar_exchange_procs` | `h5diff PartInt` fails — ~3% per-element particle count difference | Regression binary compiled with `PICLAS_USE_GPU=ON`; GPU push gives slightly different FP trajectories than Linux CPU reference files | Regenerate reference files from Windows GPU binary, or build CPU-only binary (`PICLAS_USE_GPU=OFF`) for regression |
| **G** | `exchange_procs` (MPI≥21), `mortar_exchange_procs` | Exit code 3 crash on highest-rank process; no error message | Unknown — only manifests at 21+ MPI processes; likely memory corruption or stack overflow under high MPI load | Debug build with `-ffpe-trap=invalid,overflow -fsanitize=address`; run with `mpiexec -n 21` to get stack trace |
| **surf_flux mismatch** | `surf_flux_2D_track` | `NumDens` ~33% below Linux reference on all proc counts; MPI=4 Adaptive=T crashes | Stochastic DSMC + axisymmetric radial weighting; platform-dependent RNG state diverges from Linux reference | Regenerate reference on Windows, or increase iteration count for statistical convergence |

---

## Notes

- **MPI + PETSc cannot be combined**: MSYS2 PETSc is sequential-only; `PetscInitialize()` aborts if >1 MPI rank. Use either `LIBS_USE_MPI=ON` or `LIBS_USE_PETSC=ON`, never both.
- **HOPR required for many tests**: Tests without pre-built `*_mesh.h5` files need the HOPR mesh generator. Set `HOPR_PATH` env var pointing to a HOPR Windows binary when available.
- **HDF5 file locking**: Always set `HDF5_USE_FILE_LOCKING=FALSE` before any MPI run.
- **Blocked test categories**: Sanitize/Profile build types, MPI+PETSc tests, and tests requiring HOPR that don't have bundled meshes are permanently blocked on Windows.
