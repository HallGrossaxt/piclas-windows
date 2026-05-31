# Bug G — MPICH + MUST investigation runbook (Linux)

> **Executed 2026-05-30 on WSL2 Ubuntu 26.04 — see `bugG_linux_valgrind_investigation.md` §14 for results.**
> **MUST is blocked the same way it was on OpenMPI: PICLas's `use mpi_f08` produces `mpi_*_f08_` symbols
> that MPICH 4.3.2's bindings do NOT route through C `MPI_*`, so PnMPI's wrap layer sees nothing.** The
> Technique B guards (`particle_mesh_readin.f90` 5×, `mesh_pAdaption.f90` 3×) were applied to the working
> tree and confirmed not to fix Bug G on single-node n=10 (Fisher p≈0.4 vs baseline), but landed as correct
> multi-leader hardening matching the §13.x/§16.x project pattern. The runbook below is preserved for
> reference / future tool versions.


Self-contained runbook for the next investigation step after `bugG_linux_valgrind_investigation.md` (44 ASan/UBSan
runs + 4 Valgrind runs, all clean in PICLas frames) and `bugG_windows_instrumentation_plan.md` §13 (330-run Windows
Technique A+B campaign — no Fortran-level OOB caught, Technique B guards landed as hardening).

**Why this step:** the surviving Bug G hypothesis is an **MPI shared-memory window lifetime / sync race** during
LB restart. ASan/Valgrind/UBSan are per-process tools that can't see cross-process window semantics. **MUST is
purpose-built for exactly this bug class** (window lifetime, sync epochs, buffer-reuse-before-`MPI_WAIT`,
`MPI_IN_PLACE` aliasing, request leaks). It was attempted in §12 but blocked by OpenMPI's F08 bindings calling
internal `ompi_*_f` symbols instead of C `MPI_*`, which bypasses PnMPI/MUST's C-layer interception.

**The unblock:** rebuild the toolchain on **MPICH**. MPICH's F08 bindings route through C `MPI_*`, which MUST
intercepts via PnMPI. MUST's own README uses MPICH examples.

> Estimated effort: **~1–2 h toolchain rebuild + ~30 min run + analysis**. New-toolchain risk is moderate but
> tractable (the OpenMPI 4.1.1 + parallel HDF5 1.12.1 build in §11 is the playbook).

---

## 0. TL;DR

1. `apt install mpich libmpich-dev` (or build MPICH 4.x from source if version pinning matters).
2. Rebuild parallel HDF5 1.12.1 with `CC=mpicc` from MPICH (re-use the existing source tree).
3. Rebuild PICLas Debug + MPI against MPICH, mirroring `~/piclas/build-bugG-debug` but with the MPICH wrappers.
4. Rebuild MUST 1.11.2 against MPICH (it builds cleanly on MPICH per upstream docs; no F08 shim exclusion).
5. `mustrun -np 10 ~/piclas/build-bugG-debug-mpich/bin/piclas parameter.ini` in the bugG repro kit.
6. Open `MUST_Output.html`. Look for: **WIN_LOCK/SYNC errors, IN_PLACE aliasing, IRECV/ISEND-before-WAIT,
   request leaks, premature WIN_FREE / window-state mismatches across ranks.**

---

## 1. Prereqs (re-use from §11 where possible)

The §11 stack is OpenMPI-based. We're building a parallel side-track on MPICH. **Do not overwrite the OpenMPI
build** — keep both so we can A/B compare.

Reference paths from §11 (Ubuntu, custom stack at `/home/alopp/`):
- `~/openmpi/4.1.1/` — keep
- `~/parallel-hdf5-1.12.1/` (OpenMPI build) — keep
- `~/piclas/build-bugG-debug/` (OpenMPI Debug) — keep
- `~/must-install/` (MUST against OpenMPI — blocked, but keep for reference)
- `~/bugG/` (repro kit + Valgrind logs)

New paths for this runbook:
- `~/mpich/4.2/` — MPICH install prefix
- `~/parallel-hdf5-1.12.1-mpich/` — HDF5 rebuilt on MPICH
- `~/piclas/build-bugG-debug-mpich/` — PICLas Debug on MPICH
- `~/must-install-mpich/` — MUST against MPICH
- `~/bugG-mpich/` — fresh repro working dir

---

## 2. Install MPICH

Apt-pinned MPICH first (fastest; works for MUST per their docs):

```bash
sudo apt install -y mpich libmpich-dev
mpicc --version    # should be GCC with MPICH wrappers (check `mpicc -show`)
mpiexec --version  # MPICH
```

If apt-MPICH version causes issues (rare), build from source:

```bash
cd ~ && wget https://www.mpich.org/static/downloads/4.2.2/mpich-4.2.2.tar.gz
tar xf mpich-4.2.2.tar.gz && cd mpich-4.2.2
./configure --prefix=$HOME/mpich/4.2 --with-device=ch3 \
  --enable-fortran=all --enable-fast=O2,ndebug \
  CC=gcc-11 CXX=g++-11 FC=gfortran-11 F77=gfortran-11
make -j$(nproc) && make install
export PATH=$HOME/mpich/4.2/bin:$PATH
export LD_LIBRARY_PATH=$HOME/mpich/4.2/lib:$LD_LIBRARY_PATH
mpiexec --version
```

Capture an env file for reruns:

```bash
cat > ~/bugG-mpich-env.sh <<'EOF'
# Sourced before MPICH-stack builds and runs
export PATH=$HOME/mpich/4.2/bin:$PATH
export LD_LIBRARY_PATH=$HOME/mpich/4.2/lib:$HOME/parallel-hdf5-1.12.1-mpich/lib:$LD_LIBRARY_PATH
unset OPAL_PREFIX  # OpenMPI-only; ensure not leaking from §11 env
EOF
source ~/bugG-mpich-env.sh
which mpicc mpiexec
```

---

## 3. Rebuild parallel HDF5 on MPICH

```bash
source ~/bugG-mpich-env.sh
cd ~/hdf5-1.12.1   # the source tree used in §11; if missing, fetch from upstream
mkdir build-mpich && cd build-mpich
../configure --prefix=$HOME/parallel-hdf5-1.12.1-mpich \
  --enable-parallel --enable-shared --disable-static \
  CC=mpicc FC=mpif90
make -j$(nproc) && make install
# sanity
$HOME/parallel-hdf5-1.12.1-mpich/bin/h5pcc -show     # should reference $HOME/mpich/...
```

---

## 4. Rebuild PICLas Debug on MPICH

Mirror §3 of `bugG_linux_valgrind_investigation.md` exactly, but pointing CMake at the MPICH stack:

```bash
source ~/bugG-mpich-env.sh
cd ~/piclas
mkdir build-bugG-debug-mpich && cd build-bugG-debug-mpich
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DLIBS_USE_MPI=ON \
  -DLIBS_USE_PETSC=OFF \
  -DLIBS_BUILD_HDF5=OFF \
  -DHDF5_DIR=$HOME/parallel-hdf5-1.12.1-mpich \
  -DPICLAS_EQNSYSNAME=maxwell \
  -DPICLAS_TIMEDISCMETHOD=RK4 \
  -DPICLAS_NODETYPE=GAUSS \
  -DPICLAS_POLYNOMIAL_DEGREE=N \
  -DPICLAS_PARTICLES=ON \
  -DPICLAS_LOADBALANCE=ON \
  -DPICLAS_USE_GPU=OFF \
  -DCMAKE_Fortran_COMPILER=mpif90 \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  ..
ninja piclas    # binary: ./bin/piclas
```

Apply the §11.1 + §11.2 fixes if they aren't already in the working tree (`WHOLE_ARCHIVE` Linux link branch in
`src/CMakeLists.txt`; `H5PSET_USERBLOCK_F` in the parallel-HDF5 `OpenDataFile` branch). If you're working from the
`feature/gpu-acceleration` branch they should already be present.

### Reproduce Bug G *without* MUST first

Same loop as §4 of the Valgrind investigation, but with the MPICH binary:

```bash
PICLAS=~/piclas/build-bugG-debug-mpich/bin/piclas
mkdir ~/bugG-mpich && cd ~/bugG-mpich
cp /mnt/windows/Data/PRJ/piclas-win/_bugG_repro/parameter.ini .
cp /mnt/windows/Data/PRJ/piclas-win/_bugG_repro/plasma_wave_mesh.h5 .
cp /mnt/windows/Data/PRJ/piclas-win/_bugG_repro/plasma_wave_State_000.00000000000000000.h5 .

for i in $(seq 1 20); do
  mpiexec -n 10 $PICLAS parameter.ini > run_$i.log 2>&1
  echo "run $i -> exit $?"
done
grep -lE 'SIGSEGV|signal|Backtrace|exit code' run_*.log
```

**Interpretation:**
- **Crashes (any of 20):** Bug G is also reproduced on MPICH (would be the first non-MS-MPI confirmation). Go to §5.
- **20/20 clean** (matches OpenMPI §11 = 0/44 ASan / 0/4 Valgrind): Bug G is MS-MPI-specific *also* relative to
  MPICH. **MUST will still flag the latent violation** (window lifetime / sync ordering / IN_PLACE) even though
  MPICH tolerates it. Proceed to §5 regardless.

---

## 5. Build and run MUST against MPICH

```bash
source ~/bugG-mpich-env.sh
cd ~/must-build      # the source tree from §12; if missing, clone from upstream
rm -rf build-mpich   # fresh out-of-tree build per MPICH wrappers
mkdir build-mpich && cd build-mpich
cmake \
  -DCMAKE_INSTALL_PREFIX=$HOME/must-install-mpich \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DCMAKE_Fortran_COMPILER=mpif90 \
  -DUSE_BACKWARD=OFF -DENABLE_TSAN=OFF \
  ..
make -j$(nproc) && make install
export PATH=$HOME/must-install-mpich/bin:$PATH
mustrun --version
```

Sanity check on a C MPI program (must produce `MUST_Output.html` with "no errors"):
```bash
cat > /tmp/hello_mpi.c <<'EOF'
#include <mpi.h>
int main(int argc, char**argv) { MPI_Init(&argc,&argv); MPI_Finalize(); return 0; }
EOF
mpicc /tmp/hello_mpi.c -o /tmp/hello_mpi
cd /tmp && mustrun -np 2 ./hello_mpi
ls MUST_Output.html
```

If that's clean, run MUST against PICLas:

```bash
cd ~/bugG-mpich
# clean previous outputs
rm -rf MUST_Output* MUST_*.log
mustrun -np 10 ~/piclas/build-bugG-debug-mpich/bin/piclas parameter.ini > must_run.log 2>&1
ls -la MUST_Output.html
```

> **MUST is slow** (instruments every MPI call). Expect 5–15× slowdown; the bugG repro is small, so still
> ~1–5 minutes per run.

---

## 6. What to look for in MUST_Output.html

MUST groups findings by severity (ERROR / WARNING / INFORMATION). For Bug G the relevant ERROR/WARNING categories
to grep for in the HTML or in `MUST_*.log`:

| Category | What it means for Bug G |
|----------|-------------------------|
| **MPI_Win_lock / MPI_Win_unlock state errors** | Shared-window epoch ordering violation — top suspect |
| **MPI_Win_free called while window in use** | Window lifetime race — also top suspect |
| **MPI_Win_sync / MPI_Win_flush expected but missing** | Sync discipline gap |
| **MPI_IN_PLACE on a single-process communicator** | The Technique B class — should now be guarded; if MUST still flags any, we missed a site |
| **Buffer used by MPI_ISend/IRecv reused before MPI_Wait** | LB exchange race |
| **Request leak (ISend/IRecv without Wait)** | Same |
| **Aliasing in non-blocking send/recv buffers** | LB particle exchange anti-pattern (§13.4 class) |

Each finding includes a **call stack** with `file:line` — that is the smoking gun we couldn't get from Fortran
asserts.

**If MUST finds nothing on a CLEAN run:** trigger a Bug-G-style crash explicitly. MUST runs the entire program;
even if PICLas finishes successfully, the latent violation should be flagged. If 20 runs all pass and MUST reports
zero findings, the bug is *not* in standard-MPI semantics — at that point look at MPI shared-window implementation
quirks (MS-MPI specifically), and the only remaining tool is symbol-level debugging on Windows.

---

## 7. Reporting

For each MUST finding, capture:
- Severity + category
- File:line from the stack
- The PICLas function (typically `loadbalance_*` or `particle_mpi_*`)
- The MPI window or request involved
- Whether the finding is on a guarded path (§13.x/§16.x already-fixed class) or new

Append findings as `§14 MUST results (date)` to `bugG_linux_valgrind_investigation.md`. If MUST localizes the bug:
the fix will mirror existing remediation — likely an explicit `MPI_WIN_SYNC` / `MPI_BARRIER` around the LB
restart, or a swap of `MPI_IN_PLACE` for explicit buffers (the §13.x pattern).

---

## 8. Decision tree

```
MPICH build + 20 runs no-MUST
├─ crashes ──► run mustrun
│     └─ MUST flags ERROR ──► fix → re-test on Windows MS-MPI to confirm
│           └─ MUST clean ──► bug is implementation-specific (MS-MPI semantics not violated by MPI standard)
│                              → manual source audit of shared-window sync, OR accept-as-known-limitation
└─ 20/20 clean (matches OpenMPI behavior)
      └─ run mustrun anyway — MUST may still flag the latent violation
            └─ flagged ──► same fix path as above
            └─ clean   ──► MS-MPI-implementation-specific; manual audit or accept-as-known
```

---

## 9. If MUST doesn't help: source audit checklist

Scope: **LB restart → first post-LB call into the deposit loop**. List every `MPI_Win_*` and `BARRIER_AND_SYNC`
on the shared windows the Windows instrumentation campaign localized (`bugG_windows_instrumentation_plan.md` §13):

- `N_DG_Mapping_Shared_Win`
- `NodeSource` / `NodeSourceExt` / `NodeSourceExtTmp`
- `NodeVolume_Shared_Win`
- `NodeCoords_Shared_Win`
- `Periodic_Nodes_Shared_Win`, `Periodic_nNodes_Shared_Win`, `Periodic_offsetNode_Shared_Win`
- `ElemInfo_Shared_Win`, `SideInfo_Shared_Win`, `ElemNodeID_Shared_Win`, `NodeInfo_Shared_Win`

Look for:
1. A window that is **`UNLOCK_AND_FREE`'d in finalize** but the per-rank finalize ordering during LB doesn't all-ranks-`MPI_BARRIER` first → another rank reads the freed window.
2. A `BARRIER_AND_SYNC` that's **missing between rebuild and first read** → a rank reads stale post-LB state.
3. A window whose **size changes across LB** (re-allocated) but the post-LB `MPI_WIN_LOCK_ALL` is taken before all ranks have completed their re-allocation `MPI_WIN_ALLOCATE_SHARED`.

Cheap to do if a single suspicious pattern pops out from one quick read of `loadbalance.f90` + `mesh_pAdaption.f90`
+ `pic_depo.f90`'s deallocate/allocate path.
