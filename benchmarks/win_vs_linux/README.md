# PICLas benchmark: Windows (MS-MPI) vs Linux

Speed benchmark comparing the **piclas-win** build against upstream **PICLas on Linux**,
using one PIC case and one DSMC case driven through the **reggie** regression harness.
Both cases run a **rank sweep of 1, 2, 4, 6**; the PIC case additionally sweeps the HDG
preconditioner to measure the **GAMG speedup** (algebraic multigrid vs block-Jacobi).

The whole point is a *fair* comparison, so this directory is built to make Windows and
Linux run a **byte-identical problem** with **matched compile options**. Read
"Fairness / what must match" before trusting any number.

---

## The two cases

| dir | physics | what it stresses | size | steps |
|-----|---------|------------------|------|-------|
| `pic_hempt_hdg/` | 90° HEMP thruster, electrostatic PIC with a superB background B-field | **HDG Poisson field solve** (the piclas-win hot path) + deposition + Boris push | 1275 curved hexes, N=1 | 2000 (`tEnd=2e-8`, `dt=1e-11`) |
| `dsmc_periodic3d/` | fully-periodic 3D box, pure DSMC | **DSMC particle transport + tracking + domain decomposition** | 27000 hexes, 810k particles (full-box uniform) | 1000 (`tEnd=2e-2`, `dt=2e-5`) |

Both are copied from the repo's `regressioncheck/WEK_*` suites and re-tuned for timing
(longer `tEnd` than the truncated correctness checks; load balancing off; frozen inputs).
They were chosen because they are MPI-clean and cross-platform-reproducible: no octree
(which hangs the MS-MPI build), no axisymmetric radial weighting, no adaptive boundaries.

### The GAMG sweep (PIC only)

`pic_hempt_hdg/parameter.ini` sets `PrecondType = 2,4`; reggie runs both at every rank count.
In the **PETSc** binary these map to:

* `2` = pipelined-CG + **block-Jacobi**  — the iterative baseline
* `4` = CG + **GAMG** smoothed-aggregation algebraic multigrid — the speedup under test

GAMG's advantage is a much lower iteration count (≈19 vs ≈36 per solve on this mesh),
which only pays off once the field solve dominates — hence the 2000-step `tEnd`.

> In a **non-PETSc** binary `PrecondType` selects the internal-CG preconditioner instead
> (2 = diagonal); GAMG (4) is unavailable. Use the PETSc binary for the PIC case.

---

## Binaries

These are **prebuilt release** binaries; reggie is run with `-e` so it times the exact
shipped binary and never recompiles.

| case | build dir (Windows) | key cmake options |
|------|---------------------|-------------------|
| PIC  | `build-poisson-boris-petsc-mpi` | `PICLAS_EQNSYSNAME=poisson`, `PICLAS_TIMEDISCMETHOD=Boris-Leapfrog`, `LIBS_USE_PETSC=ON`, `LIBS_USE_MPI=ON`, `CMAKE_BUILD_TYPE=Release`, `PICLAS_POLYNOMIAL_DEGREE=N`, `PICLAS_INSTRUCTION="-march=native -mtune=native"`, PETSc **3.24.5** (no Hypre, no MUMPS) |
| DSMC | `build-maxwell-dsmc-release-mpi` | `PICLAS_EQNSYSNAME=maxwell`, `PICLAS_TIMEDISCMETHOD=DSMC`, `LIBS_USE_PETSC=OFF`, `LIBS_USE_MPI=ON`, `CMAKE_BUILD_TYPE=Release`, `PICLAS_INSTRUCTION="-march=x86-64-v2 -mtune=generic"` |

> ⚠️ The two Windows builds were configured with **different `-march`** (PIC=`native`,
> DSMC=`x86-64-v2`). That's fine for the *per-case* OS-vs-OS comparison as long as **each
> Linux build matches its own Windows counterpart's `-march`**. See below.

---

## Directory layout

```
win_vs_linux/
├── README.md               <- this file
├── RESULTS.md               <- Windows (MS-MPI) baseline numbers
├── LINUX_RESULTS.md         <- Linux vs Windows comparison + the (now closed) gap investigation
├── NEXT_ON_LINUX.md         <- runbook for the Linux boot — COMPLETED 2026-07-30
├── NEXT_ON_WINDOWS.md       <- runbook for the Windows boot — COMPLETED 2026-07-30, gap resolved
├── run_benchmark.ps1        <- Windows/MS-MPI driver
├── run_benchmark.sh         <- Linux driver (mirror of the .ps1)
├── bench_env.sh             <- Linux toolchain env (GCC/OpenMPI/HDF5/PETSc/reggie paths)
├── parse_timings.py         <- reads each run's std.out -> CSV + scaling/GAMG tables
│   # investigation scripts — Windows side
├── sweep_repeats_win.sh     <- the sweep WITH repeats + both fixes -> win_timings_fixed*.csv
├── blas_threads_win.sh      <- ** the test that resolved the gap ** (OPENBLAS_NUM_THREADS=1)
├── logview_win.sh           <- PETSc -log_view capture; the drift-free per-kernel instrument
├── petsc_opt_ab_win.sh      <- interleaved -O3 vs -O1 PETSc (static lib -> pick the binary)
│   # investigation scripts — Linux side
├── decomp_linux.sh          <- epsCG sweep + HDGSkip split -> the T = C + k*iters fit
├── thp_linux.sh, thpon.c    <- huge-pages test (refuted; see the traps section of NEXT_ON_WINDOWS.md)
├── build_petsc_o1.sh        <- PETSc 3.24.5 with the Windows flags (-g -O), for a fair swap
├── petsc_opt_swap.sh        <- interleaved -O3 vs -O1 PETSc via soname swap
├── results/                 <- *_timings.csv and logview_*.txt are tracked; run_*/ output is not
├── pic_hempt_hdg/           <- PIC case (frozen mesh + BGField, GAMG sweep)
│   ├── command_line.ini     <- MPI = 1,2,4,6
│   ├── parameter.ini        <- PrecondType = 2,4 ; tEnd = 2e-8 ; DoLoadBalance = F
│   ├── analyze.ini          <- in-domain sanity check (timing is NOT taken from here)
│   ├── HEMPT_90deg_BGField.h5      <- frozen superB background field
│   ├── pre-hopr/90_deg_segment_mesh.h5   <- frozen mesh
│   └── pre-superB/, externals.ini.disabled  <- kept for provenance / regeneration
└── dsmc_periodic3d/         <- DSMC case
    ├── command_line.ini     <- MPI = 1,2,4,6
    ├── parameter.ini
    ├── analyze.ini
    └── pre-hopr/periodic_mesh.h5         <- frozen mesh
```

**Frozen inputs.** The mesh (`pyhope`) and background field (`superB`) are pre-generated
and committed as `.h5`, and the reggie externals are disabled (`externals.ini.disabled`).
Every timed run is therefore a **pure solve** on identical inputs — no mesh/field
generation, no `ln -s`, no dependence on `pyhope`/`superB` being installed on the run host.
This is also what guarantees Windows and Linux solve the same problem: **copy these `.h5`
files to the Linux box; do not regenerate them there.**

---

## Run it (Windows)

```powershell
cd <repo>\benchmarks\win_vs_linux
pwsh -File run_benchmark.ps1
```

Produces `logs\pic.log`, `logs\dsmc.log`, and `results\win_timings.csv`, and prints the
scaling and GAMG-speedup tables. Edit the `$*_BIN`, `$REGGIE`, `$PYTHON` variables at the
top of the script if your paths differ. Needs a machine with **≥ 6 physical cores** for the
6-rank point (MS-MPI does not oversubscribe by default).

> ⚠️ `run_benchmark.ps1` runs **one** run per point and does **not** apply the two fixes found on
> 2026-07-30. Single runs on this box are worth ±3–6% (±15% at 6 ranks) and two published claims
> died to that. For numbers you intend to quote, use the repeat sweep instead — it pins
> `OPENBLAS_NUM_THREADS=1`, uses the `-o3petsc` PIC binary, and reports medians:
>
> ```bash
> ./sweep_repeats_win.sh 3          # -> results/win_timings_fixed{,_raw}.csv, ~65 min
> RANKS=6 CASES=pic ./sweep_repeats_win.sh 1 /tmp/smoke   # cheap mechanics check first
> ```

---

## Reproducing on Linux (identical conditions)

**1. Build the two matching binaries.** From the PICLas source, per case:

```bash
# PIC (must match build-poisson-boris-petsc-mpi)
cmake -B build-poisson-boris-petsc-mpi -DPICLAS_EQNSYSNAME=poisson \
      -DPICLAS_TIMEDISCMETHOD=Boris-Leapfrog -DLIBS_USE_PETSC=ON -DLIBS_USE_MPI=ON \
      -DCMAKE_BUILD_TYPE=Release -DPICLAS_POLYNOMIAL_DEGREE=N \
      -DPICLAS_INSTRUCTION="-march=native -mtune=native"
cmake --build build-poisson-boris-petsc-mpi -j

# DSMC (must match build-maxwell-dsmc-release-mpi)
cmake -B build-maxwell-dsmc-release-mpi -DPICLAS_EQNSYSNAME=maxwell \
      -DPICLAS_TIMEDISCMETHOD=DSMC -DLIBS_USE_PETSC=OFF -DLIBS_USE_MPI=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DPICLAS_INSTRUCTION="-march=x86-64-v2 -mtune=generic"
cmake --build build-maxwell-dsmc-release-mpi -j
```

Use the **same PETSc version (3.24.5)** for the PIC build. GAMG (`PrecondType=4`) is native
to PETSc and needs neither Hypre nor MUMPS, so a plain PETSc matches the Windows build.

**2. Copy the frozen inputs** from this directory (the three `.h5` files) to the Linux copy
of `win_vs_linux/` — do **not** regenerate them, so both OSes solve a byte-identical problem.

**3. Install reggie** (`pip install` the repo's `reggie2.0`), then:

```bash
cd <repo>/benchmarks/win_vs_linux
# point the script at your build tree if needed:
PICLAS_ROOT=<repo> ./run_benchmark.sh
```

Produces `results/linux_timings.csv`.

### Fairness / what must match

* **CPU tuning.** `-march=native` bakes in the *build host's* CPU. For a meaningful
  Windows-vs-Linux number, either (a) run both OSes on the **same physical machine**
  (dual-boot; native, not a VM/WSL), or (b) pin an explicit identical `-march` on both OSes
  for each case. Do not compare a `native` Windows build against a `native` Linux build on
  different CPUs.
* **MPI vendor.** Windows uses **MS-MPI** (`mpiexec -n`), Linux typically **OpenMPI/MPICH**
  (`mpirun -np`). This is a genuine variable at higher rank counts, so always report the
  **1-rank point** as the vendor-neutral anchor. (reggie auto-caps MPICH to the physical
  core count to avoid its oversubscription cliff.)
* **Same binary, same flags, Release.** Both sides `CMAKE_BUILD_TYPE=Release`, same
  `PICLAS_TIMEDISCMETHOD`/`EQNSYSNAME`/`LIBS_USE_PETSC` per case. Note that
  `cmake/SetCompiler.cmake` drops **`-fstack-arrays`** on `WIN32` (gfortran ICE with LTO on
  MinGW), so the Fortran flags are *not* identical out of the box; measured at ~3% on the
  PIC case (see `LINUX_RESULTS.md`).
* **BLAS threading — the big one on Windows.** ⚠️ **Set `OPENBLAS_NUM_THREADS=1` for the PIC
  case at low rank counts.** MSYS2's OpenBLAS (which the Windows PETSc links) is built
  multithreaded; Ubuntu's reference netlib BLAS is not. PETSc calls `BLASaxpy` ~110k times per
  run on vectors just large enough to trip OpenBLAS's parallelisation threshold, so it forks and
  joins a thread team 110,000 times — **54.7 µs per call against 4.1 µs on Linux.** At 1 rank
  this alone was **1.35x**, i.e. the whole of what used to be the unexplained PIC gap
  (36.70 s → 27.26 s, versus Linux's 27.47 s). It is a **low-rank effect only**: by 2 ranks it is
  within noise and by 4 ranks OpenBLAS keeps `daxpy` serial on its own, because decomposition has
  dropped each rank's vectors below its threshold. See `blas_threads_win.sh` and
  `LINUX_RESULTS.md` → "Windows-side session".
* **Third-party library flags.** `PICLAS_INSTRUCTION` only reaches PICLas' own sources — it
  does **not** touch PETSc, HDF5 or OpenBLAS. For the PIC case most of the time is spent
  *inside* PETSc, so **PETSc's own `COPTFLAGS` must match on both OSes**. Check with
  `grep '^CC_FLAGS' $PETSC_DIR/lib/petsc/conf/petscvariables` before comparing: PETSc built
  with `--with-debugging=0` but no explicit `COPTFLAGS` silently falls back to `-g -O`
  (**-O1**, generic arch), which is what the Windows install at `petsc-msmpi` has;
  `petsc-msmpi-O3` is the `-O3 -march=native` counterpart.
  **Confirmed 2026-07-30: this asymmetry is real** — Windows PETSc is `-g -O`, Linux PETSc is
  `-O3 -march=native -mtune=native`. It is worth **11.4%** on Linux (`petsc_opt_swap.sh`) but only
  **3.2–3.6%** on Windows, because a sixth of the Windows runtime sat inside OpenBLAS where PETSc's
  flags have no reach. Note the Windows PETSc is a **static `libpetsc.a`**, so which PETSc you get
  is fixed at link time — there is no DLL search order to worry about, and the two builds
  `build-poisson-boris-petsc-mpi` / `-o3petsc` are the way to switch.
* **Determinism.** DSMC uses GFortran's xoshiro256** RNG, which is platform-independent, so
  Windows and Linux march the *identical* particle population — the DSMC comparison is doing
  exactly the same work on both.
* **The PIC case is chaotic — do not expect matching final states.** A given binary is
  bit-reproducible run to run (verified: two runs of the same exe give a byte-identical
  `DG_Solution`), but *any* perturbation of the solver diverges over 2000 steps. Measured on
  the 1-rank point, final `DG_Solution` L2 relative difference:
  `bjacobi` vs `GAMG` on one PETSc **1.2e-1**; PETSc `-O1` vs `-O3` with one preconditioner
  **1.1e-1**; and `PartData` differs in particle *count* (12 vs 15). The two preconditioners
  the benchmark itself sweeps already disagree by ~12%, and both are accepted — so this is a
  property of the case, not a defect. It does mean the timing comparison is valid (identical
  algorithm, identical inputs) while a **state-file diff is not a meaningful cross-check here**.

---

## Correctness cross-check

Timing means nothing if the two builds computed different things — but *how* you check differs
per case.

**DSMC** marches an identical particle population on both OSes (platform-independent RNG), so a
state diff is a valid check:

```bash
h5diff -r -d 1e-10 win/.../periodic_State_000.02000000000000000.h5 \
                   linux/.../periodic_State_000.02000000000000000.h5
```

**PIC: do not diff the state file.** As measured above, this case diverges chaotically over
2000 steps — even the two preconditioners the benchmark itself sweeps end ~12% apart in L2, and
particle counts differ. `h5diff -d 1e-8` will always fail and tells you nothing. Check instead
that both sides ran the same algorithm on the same inputs:

```bash
grep -a "Iterative solver\|#Procs\|PICLAS FINISHED" .../std.out   # same solver, ranks, and it finished
```

plus the `analyze.ini` in-domain guard that reggie already applies. For a genuine PIC
cross-platform *correctness* check, use a short run (tens of steps, before divergence
amplifies) rather than the 2000-step timing configuration.

(The `analyze.ini` in each case is only a cheap "particles still in the domain" guard so
reggie is happy; the benchmark times are read from `std.out`, not from the analyze result,
so an analyze flag never corrupts the numbers.)

---

## Reading the results

`parse_timings.py` reads each run's `std.out` and pulls, straight from PICLas' own output:
rank count (`#Procs`), pure-solve wall time (`PICLAS FINISHED! [ N sec ]`), and — for PIC —
the solver type (`cg with gamg` vs `pipecg with bjacobi`). It writes a CSV and prints:

* **strong scaling** per (case, solver): speedup and parallel efficiency vs the 1-rank time;
* **GAMG speedup**: `t(block-Jacobi) / t(GAMG)` at each rank count.

Compare the two OSes once both CSVs exist:

```bash
python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv
```

prints a side-by-side table with the `linux/win` wall-time ratio per (case, solver, ranks).

---

## Tuning knobs

* **Rank sweep** — `command_line.ini` (`MPI = 1,2,4,6`).
* **Run length** — `parameter.ini` `tEnd` (longer = field/collision solve dominates more,
  less startup/IO noise; remember to update the `analyze.ini` state-file time if you change PIC `tEnd`).
* **GAMG sweep** — `pic_hempt_hdg/parameter.ini` `PrecondType = 2,4`.
* **Load balancing** — off by default (`DoLoadBalance=F`) for clean, deterministic
  per-rank timings; turn on for a "realistic production" number instead.
