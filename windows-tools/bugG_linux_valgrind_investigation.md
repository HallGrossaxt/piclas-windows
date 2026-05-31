# Bug G — Linux + Valgrind Investigation Runbook

**Purpose:** pin down Bug G (flaky exit-code-3 SIGSEGV after load balance) on Linux, where Valgrind's
shadow-memory detection is *deterministic* and *not* timing/layout-dependent — unlike every Windows tool tried so
far, all of which suppressed it.

> Self-contained: you can run this whole plan from a fresh Ubuntu session. The repo lives on the Windows
> partition at `…/piclas-win/piclas-win-master`; mount it read-write (ntfs-3g) or `git clone` a fresh copy on the
> Linux ext4 disk (recommended — builds are faster and avoid NTFS permission quirks).

---

## 0. TL;DR

1. `apt install` the toolchain + OpenMPI + parallel HDF5 + **valgrind** (see §2).
2. Build a **CPU Debug** maxwell-RK4 binary (no GPU, no PETSc, `PICLAS_LOADBALANCE=ON`) — §3.
3. **Reproduce first *without* Valgrind** at `mpirun -np 10` in the repro kit — §4.
   - *Crashes on Linux* → Bug G is real & cross-platform; go to Valgrind.
   - *Never crashes on Linux (e.g. 20/20 clean)* → strong evidence it's **MS-MPI-specific**; Valgrind still
     finds the latent invalid access that MS-MPI is stricter about.
4. Run under **`valgrind --tool=memcheck`** with per-rank logs — §5. Look for *Invalid write/read* or
   *uninitialised value* during the **first post-load-balance timestep**.
5. If memcheck is clean, escalate to an **MPI correctness checker** (MUST) / Helgrind on shared-mem windows — §6.

---

## 1. What Bug G is (recap)

| Attribute | Detail |
|-----------|--------|
| **Symptom** | Exit code 3, **SIGSEGV** on the highest-rank process, *no* PICLas `ABORT` message, raw-address backtrace |
| **When** | Right after load balance (`PICLAS RUNNING!` / `MinWeight/MaxWeight` printed), in the **first post-LB timestep** |
| **Flaky** | Non-monotonic in rank count: `n=10` fails ~deterministically (4/4 on the GPU-release binary, ~1/3 on debug-CPU), `n=16` passes 4/4. NOT CPU oversubscription. |
| **Not GPU** | A CPU-only build also crashes → not the GPU memory layer. |
| **Heisenbug** | Suppressed by **gdb**, page-heap, ASLR-off, and even **printf** instrumentation → timing/heap-layout sensitive. |
| **Affected** | `NIG_tracking_DSMC/exchange_procs` (MPI≥21), `mortar_exchange_procs`; `NIG_PIC_maxwell_RK4_p_adaption/3D_periodic_CVWM` (n=10 deterministic, n=11/12/15 flaky) |

**Leading hypothesis (from the Windows code audit):** heap corruption from an **out-of-bounds write during the
load-balance restart** — an array sized for the *pre*-balance decomposition written with *post*-balance sizes in
the first resumed timestep (the §16.13 `IsPushArr` class, but in a CPU-side array). Alternatively an **MPI
ordering issue** in the LB particle-exchange path (a non-blocking send/recv buffer reused/freed before
`MPI_WAIT(ALL)`, or an `MPI_IN_PLACE`/aliasing case). On Windows `-fbounds-check` never fired → it's a *raw memory
reference* (pointer / C-interop / MPI buffer / heap), exactly what Valgrind memcheck is built to catch.

**Why Linux + Valgrind:** memcheck reports the invalid memory *access at the instant it happens* via shadow
memory — it does **not** depend on whether the access leads to a crash, and is not perturbed by timing the way
gdb/page-heap/printf are. So even if the program runs to completion under Valgrind, the offending read/write is
still flagged with a file:line backtrace.

---

## 2. Requirements (Ubuntu)

```bash
sudo apt update
sudo apt install -y \
  build-essential gfortran cmake ninja-build git \
  openmpi-bin libopenmpi-dev \
  libhdf5-openmpi-dev \
  liblapack-dev libopenblas-dev \
  zlib1g-dev \
  valgrind gdb \
  python3 python3-pip
# (optional, for reggie-driven runs / h5 inspection)
pip3 install --user h5py numpy
```

Versions to note (record them in your findings): `gfortran --version`, `mpirun --version`,
`valgrind --version`, `cmake --version`, `dpkg -l | grep hdf5`.

> **MPI choice:** OpenMPI is fine. For the *cleanest* Valgrind output, either use the OpenMPI Valgrind
> suppression file (§5) or, if you have time, rebuild OpenMPI `--enable-memchecker --with-valgrind`. MPICH is an
> alternative that is often quieter under Valgrind (`sudo apt install mpich libmpich-dev` and rebuild PICLas
> against it). Try OpenMPI + suppressions first.

---

## 3. Build a CPU Debug binary

The Bug-G repro is **maxwell + RK4 + PIC + load balance** (the `3D_periodic_CVWM` / `_bugG_repro` case). Build the
matching config on Linux, CPU-only, Debug, with MPI:

```bash
# from a fresh clone on ext4 (recommended):
git clone <piclas-remote-or-copy> piclas && cd piclas
# (or: cp -r /mnt/windows/Data/PRJ/piclas-win/piclas-win-master ~/piclas && cd ~/piclas)

mkdir build-bugG-debug && cd build-bugG-debug
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DLIBS_USE_MPI=ON \
  -DLIBS_USE_PETSC=OFF \
  -DLIBS_BUILD_HDF5=ON \
  -DPICLAS_EQNSYSNAME=maxwell \
  -DPICLAS_TIMEDISCMETHOD=RK4 \
  -DPICLAS_NODETYPE=GAUSS \
  -DPICLAS_POLYNOMIAL_DEGREE=N \
  -DPICLAS_PARTICLES=ON \
  -DPICLAS_LOADBALANCE=ON \
  -DPICLAS_USE_GPU=OFF \
  ..
ninja piclas        # binary: ./bin/piclas
```

Notes:
- **`-DLIBS_BUILD_HDF5=ON`** builds a parallel HDF5 with the MPI compiler — most reliable. If you prefer the
  system package, use `-DLIBS_BUILD_HDF5=OFF -DHDF5_DIR=/usr/lib/x86_64-linux-gnu/hdf5/openmpi` (parallel HDF5).
- **Debug = `-O0 -g`** is ideal for Valgrind (clear line attribution). PICLas Debug also adds Fortran
  `-fbounds-check`/`-ffpe-trap`/`-finit-real=snan` — keep them: bounds-check may now fire on Linux (it never did
  on Windows), and that alone could pinpoint the array. If `-ffpe-trap` aborts on a benign FP *before* the heap
  bug, rebuild once with `CMAKE_BUILD_TYPE=RelWithDebInfo` (`-O2 -g`, no FP trap) for the Valgrind pass.
- This binary should be the analogue of the Windows `build-rk4-debug-cpu` that reproduced Bug G ~1/3 of the time.

---

## 4. Reproduce *without* Valgrind first (critical)

Use the bundled repro kit (parameter.ini + mesh + restart State), copied from `piclas-win/_bugG_repro/`:

```bash
mkdir ~/bugG && cd ~/bugG
cp /mnt/windows/Data/PRJ/piclas-win/_bugG_repro/parameter.ini .
cp /mnt/windows/Data/PRJ/piclas-win/_bugG_repro/plasma_wave_mesh.h5 .
cp /mnt/windows/Data/PRJ/piclas-win/_bugG_repro/plasma_wave_State_000.00000000000000000.h5 .   # restart file
PICLAS=~/piclas/build-bugG-debug/bin/piclas

# run n=10 many times; Bug G is flaky so loop
for i in $(seq 1 20); do
  mpirun -np 10 $PICLAS parameter.ini > run_$i.log 2>&1
  echo "run $i -> exit $?"
done
grep -lE 'SIGSEGV|signal|Backtrace|exit code' run_*.log
```

**Interpretation:**
- **Crashes on Linux (any of 20):** Bug G is real and cross-platform → proceed to Valgrind (§5). Note the
  crash rate vs rank count (also try `-np 11 12 15 16`).
- **Never crashes (20/20 clean):** very informative — it means Bug G is **MS-MPI-specific** (OpenMPI/MPICH
  tolerate whatever MS-MPI chokes on). The fix then targets the PICLas↔MPI interaction (a buffer reused before
  `MPI_WAIT`, or an `MPI_IN_PLACE`/aliasing that's only fatal under MS-MPI). **Still run Valgrind (§5)** — it will
  flag the latent invalid access (e.g. a read of freed/uninitialised buffer) even though OpenMPI didn't crash.

> If `mpirun` complains about oversubscription with `-np 10` on a <10-core VM, add `--oversubscribe`.
> Bug G is decomposition-, not core-count-, dependent, so oversubscription is fine for repro.

---

## 5. Valgrind memcheck

Run each rank under memcheck with **separate per-rank logs** (`%p` = PID):

```bash
cd ~/bugG
SUPP=$(find /usr -name 'openmpi-valgrind.supp' 2>/dev/null | head -1)
mpirun -np 10 \
  valgrind --tool=memcheck \
           --leak-check=no \
           --track-origins=yes \
           --read-var-info=yes \
           --num-callers=40 \
           --error-exitcode=99 \
           ${SUPP:+--suppressions=$SUPP} \
           --log-file=vg.%p.log \
  $PICLAS parameter.ini
# inspect:
grep -nE 'Invalid (write|read)|uninitialised|Process terminating|Invalid free' vg.*.log
```

**What to look for** (in time order within the logs):
- An **`Invalid write of size N`** or **`Invalid read`** whose backtrace lands in the **load-balance / particle
  exchange / metrics** code (see §7), occurring right after the LB restart messages. That is the smoking gun.
- **`Use of uninitialised value`** with `--track-origins=yes` pointing at an MPI receive buffer → indicates a
  non-blocking recv consumed before its `MPI_WAIT` (the ordering-race hypothesis).
- Address descriptions like *"N bytes after a block of size M alloc'd"* → confirms the *pre/post-balance size*
  mismatch hypothesis (array allocated for the old decomposition, written with new sizes).

**Caveats:**
- Valgrind slows execution ~20–50×; the repro sim is tiny (one LB + first post-LB step), so it's still seconds–minutes.
- **MPI shared-memory windows** (`MPI_Win_allocate_shared`, used heavily by PICLas) are *cross-process* — memcheck
  is per-process and may not track a write by rank A that rank B over-reads. If the smoking gun is in a shared
  window, memcheck per-rank may be quiet there; note this and lean on §6 + code audit.
- Expect MPI-internal noise; that's what the suppression file is for. Filter to frames in `src/…` PICLas code.

---

## 6. If memcheck is clean → escalate

- **MPI correctness checker — MUST** (preferred for MPI buffer/ordering bugs):
  `sudo apt install … ` (MUST is usually built from source: https://itc.rwth-aachen.de/must/). Run
  `mustrun -np 10 $PICLAS parameter.ini`; it flags buffer-reuse-before-wait, aliasing, and request leaks — exactly
  the LB-exchange hypothesis. Alternatively **PARCOACH** or **Intel Inspector** (`inspxe-cl -collect mi3`).
- **Helgrind / DRD** (`valgrind --tool=helgrind`): only useful if PICLas was built with OpenMP threading
  (`PICLAS_…OPENMP`?). For pure MPI it adds little; skip unless threads are involved.
- **AddressSanitizer** as a cross-check (fast, deterministic heap-OOB detector): rebuild with
  `-DCMAKE_BUILD_TYPE=Sanitize` if PICLas exposes it, or add `-fsanitize=address -g` to the Fortran/C flags and
  run `mpirun -np 10 $PICLAS …`. ASan catches heap/stack OOB with a precise backtrace and is much faster than
  Valgrind — a good first deterministic pass alongside memcheck.

---

## 7. Source paths to audit (LB restart + particle exchange)

The crash is in the **first post-load-balance timestep**. The Windows audit found the obvious paths "clean" but
that audit was manual; Valgrind/ASan should point at the exact line. Prime suspects:

| File | What to check |
|------|---------------|
| `src/loadbalance/loadbalance.f90` | the redistribution driver; arrays resized across the balance |
| `src/loadbalance/loadbalance_metrics.f90` | `ExchangeVolMesh` (`MPI_ALLTOALLV` of per-element metrics) — buffer sizing pre/post balance |
| `src/particles/particle_mpi/particle_mpi.f90` | `IRecvNbOfParticles` / `SendNbOfParticles` / `MPIParticleSend` / `MPIParticleRecv` — non-blocking buffers, `MPI_WAIT` ordering, zero-count guards |
| `src/mesh/mesh_pAdaption.f90` | `N_DG_Mapping` shared window (`(3,nGlobalElems)`) preserved across LB; writes after rebalance |
| `src/mesh/mesh.f90` | `FinalizeMesh` — what is freed vs preserved during LB (`IF(.NOT.PerformLoadBalance…)`) |
| `src/timedisc/timedisc_TimeStepByLSERK.f90` | first resumed RK stage; any array allocated *once at init* and indexed by post-LB element/particle counts (the §16.13 `IsPushArr` class) |

Grep helpers:
```bash
grep -rn "ALLOCATE\|SAVE\|MPI_WAIT\|MPI_IRECV\|MPI_ISEND\|MPI_IN_PLACE" src/loadbalance src/particles/particle_mpi
```

---

## 8. Decision tree / what each outcome means

```
Reproduce n=10 (no Valgrind), 20 runs
├─ crashes on Linux ──────────────► real cross-platform bug
│     └─ Valgrind memcheck/ASan ──► should pinpoint the invalid write → FIX the array sizing / buffer
│           └─ if Valgrind clean ──► MPI-ordering race → MUST/PARCOACH, then add MPI_WAITALL/explicit buffer
└─ 20/20 clean on Linux ──────────► MS-MPI-specific (OpenMPI tolerates it)
      └─ Valgrind memcheck/ASan ──► flags the latent invalid access MS-MPI is strict about → fix it (helps both)
            └─ if also clean ─────► likely an MS-MPI semantics assumption (e.g. MPI_IN_PLACE on a sub-comm, or
                                     message-ordering) — re-audit §7 for the §13.x/§16.x MS-MPI pattern; the fix
                                     is the usual explicit-buffer / MPI_WAITALL guard. Confirm by testing on the
                                     Windows MS-MPI build.
```

A clean Linux run is **not** a dead end — it localises the bug to the MS-MPI interaction, which is the recurring
bug class of this whole port (§13.1, §13.4, §16.9, §16.10, §16.14–16.16, §16.21–16.23), all fixed by
explicit-buffer / `IF(nLeaderGroupProcs.GT.1)` / `MPI_WAITALL` patterns.

---

## 9. Repro kit reference (`piclas-win/_bugG_repro/`)

Self-contained inputs already captured on the Windows side:
- `parameter.ini` (maxwell RK4, `N=5`, `DoLoadBalance=T`, `DoInitialAutoRestart=T`, 6× periodic BCs, CVWM
  deposition, `Particles-MPIWeight=0.02`)
- `plasma_wave_mesh.h5` (1000-cell mesh)
- `plasma_wave_State_000.00000000000000000.h5` (restart file)

Windows evidence in the kit (for comparison): `gdb_n10_t*.log` (all "exited normally" — gdb suppresses it),
`naslr_t*.log` (ASLR-off suppresses it), `bisect_t*.log` (printf suppresses it), `drmem_*` (Dr.Memory blocked by
Defender). The Windows trigger: GPU-release binary `mpiexec -n 10` = 4/4 crash un-instrumented; `build-rk4-debug-cpu` ≈ 1/3.

---

## 10. Record your findings

Capture, per run: rank count, crash y/n (and which rank), Valgrind/ASan first error with the **`src/…` file:line**,
and the `mpirun`/`valgrind`/`gfortran` versions. If you find the offending line, the fix almost certainly mirrors
the existing MS-MPI remediations in this port (explicit send/recv buffers, `MPI_WAITALL` before buffer reuse,
or sizing an array by the *current* (post-LB) element/particle count rather than a cached init value).

---

## 11. Findings — Linux + ASan + Valgrind run (2026-05-29)

**Environment:** Ubuntu (kernel 6.17), 16 cores. Self-consistent custom stack under `/home/alopp`:
GCC 11.2.0, OpenMPI **4.1.1**, parallel HDF5 1.12.1 (relocated from `/home/user`; see env note below).
Valgrind 3.22.0, CMake 3.28.3, binutils/ld stricter than the original build host.

### Result: Bug G does NOT reproduce on Linux/OpenMPI. PICLas is memory-clean.

| Tool | Build | Runs | Result |
|------|-------|------|--------|
| **ASan + UBSan + bounds-check** (`CMAKE_BUILD_TYPE=Sanitize`) | CPU, MPI, no PETSc, parallel HDF5 | n=10 ×20, n=11/12/15/16 ×6 each (**44 total**) | **0 crashes, 0 ASan/UBSan errors.** Every run traversed `PERFORMING LOAD BALANCE` → first post-LB timestep → `PICLAS FINISHED!` |
| **Valgrind memcheck** `--track-origins=yes` (`CMAKE_BUILD_TYPE=Debug`) | same config, no ASan | n=10 ×4 | **0 PICLas-source errors.** Only finding was a benign OpenMPI-internal artifact (see below), suppressed → ERROR SUMMARY 0. |

The ASan pass covers heap/stack OOB (the LB array-sizing hypothesis); the Valgrind pass additionally covers
**uninitialised / freed-buffer reads incl. MPI buffers** (the recv-before-`MPI_WAIT` hypothesis) — ASan cannot see those.
Both are clean in PICLas frames. n=10 (the Windows-deterministic trigger, 4/4 GPU-release / ~1/3 debug-CPU) is **0/20 here.**

The one Valgrind finding was `writev(...) points to uninitialised byte(s)` with a backtrace entirely in OpenMPI/PMIx
(`pmix_ptl_base_send_handler` ← `mca_btl_base_vader_modex_send`) — the vader shared-memory BTL shipping struct padding
during `MPI_Init`. Not PICLas, fires once at startup, unrelated to LB. Not covered by the stock
`/usr/share/openmpi/openmpi-valgrind.supp` only because that file targets system OpenMPI 4.1.6, not custom 4.1.1.
A one-rule custom suppression (`writev` ← `fun:pmix_ptl_base_send_handler`) removes it.

### Conclusion (terminal branch of the §8 decision tree)

Clean ASan **and** clean Valgrind on Linux ⇒ **Bug G is MS-MPI-specific.** OpenMPI tolerates whatever MS-MPI rejects.
The bug is an **MS-MPI semantics assumption**, not a raw heap OOB. Next action is the §7 re-audit for the MS-MPI
pattern (buffer reused/freed before `MPI_WAITALL`; `MPI_IN_PLACE`/aliasing on a sub-comm; message-ordering); the fix
is the usual explicit-buffer / `MPI_WAITALL` / `IF(nLeaderGroupProcs.GT.1)` guard. **Confirm any fix on the Windows
MS-MPI build** — the Linux build cannot regression-test this class.

### Two REAL bugs found & fixed to get the Linux build running (both genuine port defects)

1. **`src/CMakeLists.txt` — Linux link branch** (`add_lib_shared` / `add_exec`): the WIN32 branch links
   `libpiclasstatic` into `libpiclas.so` with `WHOLE_ARCHIVE` and links executables against `${linkedlibs}`; the
   Linux/ELSE branch did neither. Modern GNU `ld` (default `--no-copy-dt-needed-entries`) then (a) garbage-collects
   `timedisc.f90.o` from the `.so` (main-program-only entry point) and (b) rejects the indirect `mpi_finalize_f08`
   symbol. **Fix:** apply the WIN32 remediation to the Linux branch too (`WHOLE_ARCHIVE` + exe `${linkedlibs}`).
   Linux-only / modern-binutils-only; does not affect Windows.

2. **`src/io_hdf5/io_hdf5.f90` `OpenDataFile`** — the `#if USE_MPI_HDF5` (parallel HDF5) create branch never set the
   HDF5 userblock size (no `H5PSET_USERBLOCK_F`, and the FCPL was not passed to `H5FCREATE_F`); only the sequential
   `#else` branch did. So State files written with **parallel HDF5 + a userblock** (here ~95 KB) had the HDF5
   signature land off the userblock boundary → unreadable on reopen ("file signature not found") → the
   `DoInitialAutoRestart` write/restart aborts **before** load balance, even at np=1. **Fix:** mirror the sequential
   branch's `H5PSET_USERBLOCK_F` (next power of 2 ≥ content) and pass `creation_prp` to `H5FCREATE_F`. This affects
   **any** parallel-HDF5 build, not just Windows — worth upstreaming.

## 12. §7 MS-MPI code audit (2026-05-29)

Audited the post-load-balance hot path for the maxwell-RK4-PIC + CVWM-deposition + p-adaption repro
(`NIG_PIC_maxwell_RK4_p_adaption/3D_periodic_CVWM`). Two bug classes were checked: (A) non-blocking buffer/request
lifecycle, and (B) the documented `MPI_IN_PLACE`-on-1-member-subcommunicator class (§13.x/§16.x).

### A) Non-blocking buffer/request lifecycles — CLEAN (consistent with clean Linux ASan/Valgrind)

| Path | Verdict |
|------|---------|
| `particle_mpi.f90` `IRecvNbOfParticles`/`SendNbOfParticles`/`MPIParticleSend`/`MPIParticleRecv` | Post/wait guards match; for this case `useDSMC=.F.` so `nPartsRecv(1)==0 ⟺ SUM==0` (the (1)-vs-SUM guard asymmetry at lines 624 vs 781 is inert here). `PartSendBuf`/`PartRecvBuf` freed (1017/1018) **after** all `MPI_WAIT`s. Recv buffers sized from a count exchanged first → no truncation. Clean. |
| `pic_depo_method.f90` `DepositionMethod_CVWM` | `RecvRequest(1:nNodeRecv…)`/`SendRequest(1:nNodeSend…)` all posted over `1..n` and all waited; charge exchange fully completes before the current exchange reuses the arrays. Clean. |
| `pic_depo.f90` `InitializeDeposition` NonSym setup | `IRECV`/`ISEND`/`WAIT` over identical `iProc` ranges (all but myRank) → no un-posted request waited. Clean. |
| `loadbalance_metrics.f90` `ExchangeVolMesh` | Blocking `MPI_ALLTOALLV`, separate send/recv buffers, deallocate after. Clean. |
| `loadbalance.f90` weight reductions | `MPI_REDUCE`/`MPI_ALLREDUCE`/`MPI_BCAST` with separate buffers (no `MPI_IN_PLACE`). Clean. |

### B) `MPI_IN_PLACE` on `MPI_COMM_LEADERS_SHARED` — RULED OUT for the single-node n=10 trigger

26 inline sites tree-wide. Triaged for the maxwell-CVWM case **on a single node** (where `MPI_COMM_LEADERS_SHARED`
has 1 member — the documented MS-MPI corruption trigger):

- **Skipped on single node:** `mesh_pAdaption.f90:492/509` (gated by `nComputeNodeProcessors.NE.nProcessors`).
- **Already guarded** (`IF(nLeaderGroupProcs.GT.1)`, Bug D fix): `particle_bgm.f90:1607/1714`.
- **Harmless zero-into-zero:** `particle_mesh_readin.f90:182/197` (post-LB `PerformLoadBalance` branch) and `228/243/258`
  — unguarded by `nLeaderGroupProcs.GT.1`, but the pre-placed value is `offsetComputeNodeElem` / `N_DG_Mapping(1,1+offSetElem)`
  which is **0 on a single node**, so MS-MPI zeroing it is a no-op. The `DO iProc=1,nLeaderGroupProcs-1` loops are empty (n=1).
- **Not active / cosmetic in this case:** radiation, `surfacemodel_analyze.f90` (surface), `dielectric.f90` (needs `DoDielectric`),
  `loaddistribution.f90:1337` + `globals.f90:1593` (memory-stat reduces).

⇒ For single-node n=10, **no reachable `MPI_IN_PLACE`-on-`LEADERS_SHARED` site can corrupt** — this class is **not** Bug G's
trigger here. (It *would* matter on a multi-leader Windows config; see hardening below.)

### Surviving hypotheses (consistent with: Heisenbug, rank-count-dependent, highest-rank, per-process tools clean)

1. **Cross-process shared-memory-window over-read/write** (`MPI_Win_allocate_shared`: `N_DG_Mapping_Shared`,
   `NodeSource`/`NodeVolume`, `ElemInfo`/`SideInfo_Shared`). Per the §5 caveat, a rank-A write past its slice into
   rank-B's region of a shared window is **invisible to per-process ASan/Valgrind** — exactly the gap here. The
   `N_DG_Mapping` window is *preserved* across LB (`Build_N_DG_Mapping` `IF(PerformLoadBalance)` branch does nothing,
   line 456); audit whether the per-rank `offSetElem`/DOF offsets into it remain in-bounds after redistribution. **Top suspect.**
2. **MS-MPI shared-window/`MPI_Win` semantics** strictness (sync/lock epoch ordering) vs OpenMPI — also invisible to memcheck.

### MUST attempt (2026-05-29) — BLOCKED by MPI F08 bindings on OpenMPI

MUST v1.11.2 was successfully built against the custom stack (C/C++ on system GCC 13 to match system libxml2/ICU;
Fortran on gfortran 11.2 for OpenMPI 4.1.1 `.mod` compat; `-DUSE_BACKWARD=OFF -DENABLE_TSAN=OFF`; Fortran flag
`-I/home/alopp/openmpi/4.1.1/include`). It works on C test programs (`MUST_Output.html` produced, "no errors").

**But MUST produces no output for piclas — or even a trivial `use mpi_f08` program.** Root cause (symbol-level
confirmed): piclas uses the **MPI F08 interface** (`mpi_finalize_f08_`, `TYPE(MPI_Request)`, …). OpenMPI's F08
bindings call the *internal* `ompi_finalize_f` symbol — **not** the C `MPI_Finalize` nor `PMPI_Finalize` — so they
bypass PnMPI/MUST's C-layer interception entirely. MUST's F77 wrappers don't match the `*_f08_` symbols, and MUST's
`mpi-handle-shim` **explicitly excludes** F08 (`exclude_strings` = `f2f08, f082c, f082f, …`). ⇒ **MUST cannot
instrument an `mpi_f08` + OpenMPI application.** (MUST install kept at `~/must-install`; envfile `~/must-build/must_env.sh`.)

**To actually run MUST, the app's Fortran MPI calls must route through the C MPI layer** — i.e. build the stack
against **MPICH** (MPICH's F08 bindings call C `MPI_*`, which PnMPI intercepts; MUST's own README uses MPICH examples).
That requires rebuilding: MPICH → parallel HDF5-on-MPICH → piclas-on-MPICH (Debug) → MUST-on-MPICH (~1–2 h, new
toolchain risk). Alternatively confirm the bug on the **Windows MS-MPI** build directly.

### Recommended next actions

1. ~~Run MUST on Linux~~ — **blocked on OpenMPI+F08 (above).** Options: (a) rebuild the stack on MPICH to enable MUST;
   (b) do the manual shared-window bounds audit (#2 below, no tooling); (c) instrument on Windows MS-MPI.
2. **Manual shared-window bounds audit:** trace `N_DG_Mapping` (and `NodeSource`/`NodeVolume`) index ranges in the first
   post-LB step vs the post-LB `offsetElem`/`nElems`/`offsetComputeNodeElem` — look for an index built from a *cached*
   (pre-LB) offset. (ASan would miss it only if the array is a shared-memory window; confirm which it is.)
3. **Cheap hardening (do regardless):** add `IF(nLeaderGroupProcs.GT.1)` to the unguarded
   `particle_mesh_readin.f90:182/197/228/243/258` and `mesh_pAdaption.f90:492/509` `MPI_IN_PLACE` gathers, to match the
   project's own §13.x/§16.x standard. Not Bug G on single node, but prevents a real multi-leader MS-MPI corruption and
   removes them from suspicion. Confirm any Bug-G fix on the **Windows MS-MPI** build.

---

### Environment gotcha (for reruns)

The custom stack was built under `/home/user` and copied to `/home/alopp`. Two things must hold or the wrappers
silently load **system** OpenMPI 4.1.6 (GCC 13/14) and C++/Fortran links break on `GLIBCXX_3.4.32`:
`export OPAL_PREFIX=/home/alopp/openmpi/4.1.1`, and `LD_LIBRARY_PATH` must list the custom OpenMPI/HDF5 **before**
`/usr/lib` but keep `/usr/lib` ahead of GCC-11's `lib64` (so system `libstdc++` still satisfies cmake/valgrind).
Captured in `~/piclas/bugG_env.sh`. Build dirs: `~/piclas/build-bugG-sanitize` (ASan), `~/piclas/build-bugG-debug`
(Valgrind). Run kit + logs: `~/bugG/` (loop in `run_loop.sh`, Valgrind logs in `~/bugG/vg/`).

---

## 14. MPICH + MUST attempt — also BLOCKED by MPI F08 bindings (2026-05-30, WSL2)

Per the §12 plan, the next step was to rebuild on MPICH (whose F08 bindings were claimed to route through C
`MPI_*` symbols that PnMPI/MUST can intercept) and re-run MUST. Executed on Ubuntu 26.04 LTS under WSL2 with
MPICH 4.3.2 + parallel HDF5 1.14.6 + GCC/gfortran 15.2.0 + MUST 1.11.2.

### Build chain completed cleanly
- `apt install build-essential gfortran cmake ninja-build mpich libmpich-dev libhdf5-mpich-dev liblapack-dev libopenblas-dev`
- Re-applied the §11.1 Linux-link fix (`src/CMakeLists.txt` `WHOLE_ARCHIVE` + `${linkedlibs}` on the ELSE branch) — needed again on Ubuntu 26.04's binutils 2.45.1
- Re-applied the §11.2 `H5PSET_USERBLOCK_F` fix on the `OpenDataFile` parallel-HDF5 create branch — needed again
- PICLas Debug + MPI built clean: `/home/alopp/piclas/build-bugG-mpich-debug/bin/piclas`
- **Baseline: 20/20 PASS on MPICH** — Bug G does not reproduce on MPICH either, matching the OpenMPI result (§11)

### MUST build fixes
- MUST 1.11.2 against MPICH 4.3.2 builds, but its PnMPI's `wrap.py` *excludes* `MPI_Info_create_env` from
  generating an `XMPI_Info_create_env` wrapper, while MUST's weaver (driven by `mpi_3_specification_unmapped.xml`
  + `MustFeaturetests.cmake`) **does** emit a reference to `XMPI_Info_create_env` in `libweaver-wrapp-gen-output-0.so`.
  Result: `[PnMPI] Can't load module … : undefined symbol: XMPI_Info_create_env`.
- Workaround: `LD_PRELOAD` a one-function stub library providing `XMPI_Info_create_env` (the function is never
  actually invoked in PICLas, which doesn't use MPI Sessions). Stub at `/home/alopp/must-stub/libxmpi_stub.so`.
  After this, `mustrun -np 2 ./hello_mpi` (C program) produced `MUST_Output.html` with "MUST detected no MPI
  usage errors nor any suspicious behavior". MUST is functional.

### The actual blocker — MPICH F08 bindings DO NOT route through C MPI

The §12 conclusion was that MPICH F08 bindings call C `MPI_*`, which PnMPI/MUST can intercept. **This is
empirically false on MPICH 4.3.2.** Verified by linking two minimal programs and inspecting their undefined
references:

| Program | `use` statement | Linker symbols | MUST output |
|---------|-----------------|----------------|-------------|
| `test_mpi.f90` | `use mpi` (F77/F90 module) | `mpi_init_`, `mpi_comm_rank_`, `mpi_finalize_` | ✅ "no MPI usage errors" |
| `test_f08.f90` | `use mpi_f08` (F08 module) | `mpi_init_f08_`, `mpi_comm_rank_f08_`, `mpi_finalize_f08_` | ❌ no `MUST_Output.html` emitted |

MPICH 4.3.2's `mpi_f08` module emits `*_f08_` symbols that go through MPICH's internal Fortran interop layer,
**not** through C `MPI_*`. PnMPI's `mpi-handle-shim/wrap.py` explicitly excludes `f2f08`, `f082c`, `f082f` from
wrapping. So the symbol-level architecture is identical to OpenMPI's: F08 bindings bypass MUST.

PICLas links with `mpi_f08` (confirmed via `nm -uD` on the built binary — `mpi_finalize_f08_` etc.).
`mustrun -np 10 piclas` runs successfully (PICLAS FINISHED), but MUST emits `[MUST-ERROR] Execution finished,
but no output found at MUST_Output.html`. MUST's wrap layer never sees a single MPI call.

`mustrun --must:language fortran` does **not** help — that option sets a config flag but PnMPI's wrap
generation is upstream of it and still excludes F08.

### Conclusion

**MUST 1.11.2 cannot instrument PICLas on either OpenMPI 4.1.1 or MPICH 4.3.2**, because both implementations'
F08 bindings emit `*_f08_` symbols that PnMPI's wrap layer is hardcoded to exclude. To unblock MUST would
require one of:
- A newer MUST version with explicit MPI-F08 wrapping (none exists publicly as of 2026-05).
- Rewriting PICLas's `USE mpi_f08` to `USE mpi` (F77/F90 module) — substantial refactor, undoes a deliberate
  modernization, and the F90 interface lacks the type-safe `TYPE(MPI_Request)` etc. that PICLas relies on.
- A different MPI-correctness tool that handles F08 (PARCOACH likely has the same limitation; Intel Inspector
  is proprietary; TotalView is proprietary).

For Bug G specifically, the remaining tractable next moves are:
1. **Manual source audit of shared-window sync discipline** around LB restart (per `bugG_must_mpich_runbook.md`
   §9 — list `MPI_Win_lock_all` / `MPI_Win_sync` / `BARRIER_AND_SYNC` calls on `N_DG_Mapping_Shared`, `NodeSource`,
   `NodeCoords_Shared`, `Periodic_*_Shared`, `ElemInfo_Shared`, `SideInfo_Shared` windows; look for asymmetric
   sync between rebuild and first read post-LB).
2. **Accept Bug G as a known limitation** — three affected tests already isolated, rest of suite is clean.
