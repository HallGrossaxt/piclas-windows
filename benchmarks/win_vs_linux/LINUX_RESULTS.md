# Results — Linux (OpenMPI) vs Windows (MS-MPI), same machine (dual boot)

Run on: 2026-07-28. Upstream **PICLas 4.2.0** on Linux vs the `piclas-win` baseline in
`results/win_timings.csv` / `RESULTS.md`. **Same physical machine, dual boot** — so these
are true OS-vs-OS numbers (identical CPU), differing only in OS + MPI vendor.

## Machine / build

- **CPU:** Intel Core i5-13400F (10 physical cores / 16 threads) — same chip on both OSes.
- **Toolchain:** GCC 11.2.0, OpenMPI 4.1.1, parallel HDF5 1.12.1 (see `bench_env.sh`).
- **Source:** PICLas 4.2.0 at `/home/alopp/piclas`.
- **PIC binary** `build-poisson-boris-petsc-mpi`: poisson + Boris-Leapfrog, MPI, Release,
  `PICLAS_POLYNOMIAL_DEGREE=N`, `-march=native`, system **PETSc 3.24.5** (plain: no Hypre,
  no MUMPS — matches Windows). Built with the **Ninja** generator (the Makefile generator's
  Fortran dep-scanner hangs on PETSc `finclude` headers; Ninja is identical and avoids it).
- **DSMC binary** `build-maxwell-dsmc-release-mpi`: maxwell + DSMC, MPI, Release, PETSc OFF,
  `-march=x86-64-v2 -mtune=generic`.
- Harness: reggie2.0 (`-e`, times the shipped binary), `mpirun -np N --oversubscribe`.
- Frozen `.h5` inputs used as-is (byte-identical problem to Windows).

## GAMG on Linux — how it was enabled

Upstream 4.2.0 has **no GAMG case** in `src/hdg/hdg_petsc.f90` (`PrecondType`: 2=pipecg+
block-Jacobi, 3=BoomerAMG/needs-Hypre, 4=undefined→abort, 10=Cholesky/needs-MUMPS). The
`piclas-win` build is itself **4.2.0 + a small GAMG patch**. That patch (`CASE(4)`: convert
the SBAIJ operator to AIJ once, then `KSPCG` + `PCGAMG`) was **ported verbatim into this
Linux build** — PCGAMG is native to PETSc, so the plain PETSc 3.24.5 runs it with no extra
libraries. Both OSes therefore run the *same* solver for `PrecondType=2` and `=4`.

## DSMC — fully-periodic 3D box (27000 elems, 810k particles, 1000 steps)

Identical work on both OSes (platform-independent RNG); all runs passed the analyze check.

| ranks | Linux [s] | speedup | parEff | Windows [s] | linux/win |
|------:|----------:|--------:|-------:|------------:|----------:|
| 1 | 388.74 | 1.00x | 100% | 397.77 | **0.98x** |
| 2 | 210.61 | 1.85x |  92% | 197.55 | 1.07x |
| 4 | 121.39 | 3.20x |  80% | 111.73 | 1.09x |
| 6 |  91.27 | 4.26x |  71% |  85.52 | 1.07x |

## PIC — HDG-Poisson HEMP thruster (2000 steps), block-Jacobi vs GAMG

| ranks | BJ Linux | BJ Win | BJ l/w | GAMG Linux | GAMG Win | GAMG l/w |
|------:|---------:|-------:|-------:|-----------:|---------:|---------:|
| 1 | 23.99 | 36.30 | **0.66x** | 33.98 | 44.70 | **0.76x** |
| 2 | 20.45 | 23.52 | 0.87x | 18.47 | 21.22 | 0.87x |
| 4 | 13.24 | 16.38 | 0.81x | 12.56 | 13.72 | 0.92x |
| 6 | 12.95 | 15.05 | 0.86x | 10.02 | 12.28 | 0.82x |

### GAMG speedup (t_blockJacobi / t_GAMG)

| ranks | Linux | Windows |
|------:|------:|--------:|
| 1 | 0.71x | 0.81x |
| 2 | 1.11x | 1.11x |
| 4 | 1.05x | 1.19x |
| 6 | 1.29x | 1.23x |

Same qualitative story on both OSes: GAMG is slower serially (multigrid setup cost on a
1275-element problem) then overtakes block-Jacobi in parallel, widening with rank count.

## Takeaways

- **Linux is faster on every case**, most on the PIC field solve: block-Jacobi 0.66x and
  GAMG 0.76x serially (Linux ~30% faster), DSMC within 2% at the 1-rank anchor.
- ~~**Multi-rank DSMC is the one place Windows edges ahead** (~1.07–1.09x)~~ — **this did not
  reproduce**; see "Repeatability" below. A re-run gives 1.00x/1.03x/0.93x at 2/4/6 ranks, i.e.
  Linux ahead at 6. Treat multi-rank DSMC as **a tie within measurement scatter**.
- Since it's the **same CPU (dual boot)**, hardware is excluded. But that does **not** make
  these numbers pure "OS" effects — see the next section: at least part of the PIC gap is a
  **build asymmetry on our side**, not a property of Windows.

## Repeatability (full Windows sweep re-run 2026-07-29)

The entire Windows sweep was re-run with the **same binaries** on the **same machine**, two days
after the baseline. It does not reproduce to better than a few percent:

| | 1 rank | 2 | 4 | 6 |
|---|---:|---:|---:|---:|
| DSMC (rerun/July) | 1.05x | 1.06x | 1.05x | **1.15x** |
| PIC bjacobi | 1.03x | 1.03x | 1.04x | **1.12x** |
| PIC GAMG | 1.04x | 1.04x | 1.03x | **1.08x** |

Everything is slower on the re-run, systematically, and **worst at 6 ranks** (cause not
established — background load or thermal behaviour under sustained all-core load are the
obvious candidates). Consequences:

- **Single-run differences below ~5% (below ~15% at 6 ranks) are not meaningful.** The
  Windows-vs-Linux ratios in the tables above are single runs taken in *different sessions*, so
  they inherit this drift. Only the large PIC gap (0.64–0.66x, reproduced in both sessions)
  survives it comfortably.
- **Same-session ratios are far more trustworthy**, because the drift cancels. The GAMG-vs-
  block-Jacobi speedup — measured within one session — reproduced almost exactly
  (July 0.81/1.11/1.19/1.23 vs re-run 0.80/1.11/1.20/1.27 at 1/2/4/6 ranks).
- To make the OS comparison solid, both sides need **repeats**, ideally interleaved, rather than
  one run per point.

## Why is PIC 0.66x? (investigation 2026-07-29 — partly open)

The gap is **not uniform**, which is the key constraint on any explanation: at 1 rank (no MPI
in play, same silicon) DSMC is at **parity (0.98x)** while PIC is **0.66x**. So the cause
must be specific to the PIC binary, not a blanket Windows penalty. Ruled out by inspection:

- **BLAS** — Windows PETSc links **OpenBLAS** (`BLASLAPACK_LIB = -lopenblas`), not the slow
  f2c reference fallback that usually explains this on Windows.
- **Compiler age** — Windows is on GCC **15.2.0** (MSYS2/UCRT64), Linux on **11.2.0**. The
  newer toolchain is on the *slower* side, so this cannot be a stale-toolchain story.
- **MPI vendor** — cannot explain a 1-rank number at all.

### Tested and rejected: `-fstack-arrays`

`cmake/SetCompiler.cmake` omits `-fstack-arrays` from Release on `WIN32` (it ICEs gfortran
with LTO on MinGW) while Linux Release keeps it, so the two binaries genuinely differ by
more than the OS. Measured directly: a second PIC binary built with the flag appended via
`PICLAS_INSTRUCTION`, one-flag delta, 1 rank, 4 runs each (this build has `PICLAS_IPO` off,
so no LTO and no ICE):

| variant | PIC 1-rank, PrecondType=2 | mean |
|---|---|---|
| baseline | 38.09 / 37.64 / 37.37 / 36.89 | 37.50 s |
| `+ -fstack-arrays` | 36.31 / 36.33 / 36.07 / 36.78 | 36.37 s |

A reproducible but **small ~3% gain** (~1.1 s; GAMG moved only 0.5 s) against a ~13.5 s gap.
Real, worth having, **not the explanation**.

### Prime suspect: the PETSc library is built unoptimised

PIC links PETSc; DSMC is built `LIBS_USE_PETSC=OFF`. That is precisely the split in the data,
and the Windows PETSc install reports:

```
CC_FLAGS = ... -fvisibility=hidden -g -O
```

`-O` (i.e. **-O1**) with `-g`, generic architecture. This is the standard PETSc trap:
`--with-debugging=0` alone does **not** produce an optimised build — without an explicit
`COPTFLAGS` PETSc falls back to plain `-O`, and our configure line never passed one. The
whole linear solve (`MatMult`, `PCApply`, the GAMG hierarchy, `VecDot`) therefore runs inside
an `-O1` library, which also explains why tuning PICLas' *Fortran* flags barely moved
anything — the time isn't in PICLas' Fortran, it's in PETSc's C.

### Measured: PETSc `-O3` fixes GAMG, does nothing for block-Jacobi

PETSc 3.24.5 was rebuilt with `COPTFLAGS/FOPTFLAGS='-O3 -march=native -mtune=native'` into a
separate prefix (`/c/Data/PRJ/petsc-msmpi-O3`, configure script `petsc-src/arch-msmpi-gnu-o3.py`;
the working `petsc-msmpi` install is untouched) and PICLas relinked against it with every other
option identical. 1 rank, 3 repeats:

| | PETSc `-g -O` | PETSc `-O3 -march=native` | change | vs Linux |
|---|---|---|---|---|
| P2 block-Jacobi | 37.67 s | 37.05 s | **1.6%** | 0.66x → **0.65x** |
| P4 GAMG | 46.95 s | 40.47 s | **13.8%** | 0.76x → **0.84x** |

So the hypothesis is **half right, and wrong about the headline number**. GAMG spends
substantial time in PETSc's own C (aggregation, the multigrid hierarchy, multilevel smoothing)
and gains 13.8%. Block-Jacobi does not — `pipecg` + a block-Jacobi `PCApply` is thin, so most
of its 37 s is evidently *not* inside PETSc, and rebuilding PETSc cannot touch it.

**But the 13.8% is a 1-rank effect only.** The full rank sweep, both binaries run in the same
session (so drift cancels), gives `-O3`/`-O1`:

| ranks | 1 | 2 | 4 | 6 |
|---|---:|---:|---:|---:|
| GAMG | **0.86x** | 0.95x | 0.99x | 1.03x |
| block-Jacobi | 1.01x | 0.97x | 0.97x | 0.97x |

The GAMG win decays to nothing by 4 ranks and is inside the noise at 6. Plausibly the serial
compute fraction `-O3` accelerates (setup, smoothing) shrinks as it is divided across ranks
while communication does not. So: **`-O3` PETSc is worth having for serial/low-rank work and is
never a loss, but it is not a meaningful production win at MPI=4+** — which is where the
magnetron work actually runs. Do not expect it to move those numbers.

### Where that leaves it: the block-Jacobi gap is still unexplained

Two hypotheses tested, two refuted for the largest gap. `-fstack-arrays` gave 3%, PETSc `-O3`
gave 1.6%; the block-Jacobi point is still **0.65x** (37.05 s vs 23.99 s). What the elimination
does establish is *where the time is not*: not in PETSc (rebuilding it changed nothing here),
not in BLAS, not in the MPI layer, and not meaningfully in Fortran heap-vs-stack temporaries.
By elimination the remaining ~13 s sits in **PICLas' own Fortran on the Windows toolchain** —
candidates are GCC 15.2/MinGW codegen, the Win64 ABI's costlier calling convention on
call-heavy code, and UCRT `malloc` vs glibc `malloc`.

### Profiled (2026-07-30): it is PETSc's CG iterations, and the work is identical

**gprof is a dead end on this platform.** Two structural obstacles: all of PICLas lives in
`libpiclas.dll`, and `monstartup` sets the sampling histogram to the *executable's* text range,
so every sample inside the DLL is discarded; and linking the exe against both the DLL import lib
and `libgmon.a` duplicates `monstartup`/`_mcleanup` outright. A statically linked `-pg` exe does
build (drop whole-archive — the archive carries superB's `PROGRAM` — and add `piclaslib.f90`,
which is otherwise compiled only into the DLL), but it still produced an **empty histogram with
no call arcs**. Do not spend more time on gprof here.

Decomposition by parameter sweep works better. Two independent cuts, 1 rank, PrecondType=2:

**1. What fraction is the field solve?** `HDGSkip=100` gates both the HDG solve and the
deposition (`hdg.f90:858`, `pic_depo.f90:1346`):

| | time |
|---|---|
| full | 39.85 / 39.58 s |
| `HDGSkip=100` | 2.23 / 2.31 s |

→ **~94% is HDG solve + deposition**; push, tracking, interpolation and I/O together are ~2 s.
This case carries only ~12 particles, so deposition is negligible — it is essentially all solve.

**2. Iterations vs fixed cost?** Sweeping `epsCG` changes the CG iteration count while leaving
the per-solve assembly/post-processing untouched:

| `epsCG` | avg iters | time |
|---|---:|---:|
| 1e-1 | 2.1 | 11.42 s |
| 1e-3 | 8.5 | 25.45 s |
| 5e-5 (benchmark) | 15.5 | 40.01 s |

A linear fit on the outer two points gives `T = 6.9 s + 2.13 s x iters`, which predicts
**25.07 s** at 8.5 iterations against **25.45 s** measured (1.5% error) — the model holds. At the
benchmark's 15.5 iterations that is:

- **~33 s (83%) iteration-proportional work inside PETSc's CG** (MatMult, PCApply, dots)
- ~4.7 s fixed per-solve HDG Fortran (assembly, trace post-processing)
- ~2.2 s everything else

**3. Is Windows doing more work?** No. Per-solve iteration counts against the preserved Linux
run are effectively identical — 36/17/15/14/14/14/14/11/10/10 on Windows vs
36/19/15/14/14/12/11/12/12/10 on Linux, both summing to **155** over the first ten analyze
points. Same algorithm, same convergence, ~1.5x the wall time.

### Conclusion and the remaining hypothesis

The gap is **inside PETSc's sparse CG kernels**, executing identical work on identical silicon.
That is consistent with `-O3` buying only 1.6% here: sparse MatMult is **memory-bound**, not
compute-bound, so optimisation level barely moves it.

The leading explanation is therefore the **memory subsystem**, most plausibly **transparent huge
pages** — Linux backs large heap allocations with 2 MB pages by default, Windows uses 4 KB pages
unless a process explicitly requests large pages (which needs `SeLockMemoryPrivilege`). The trace
system here is ~17k DOFs and the operator is on the order of 10–20 MB, so with 4 KB pages the
irregular gather in MatMult walks several thousand pages and puts real pressure on the L2 TLB,
where 2 MB pages would need a handful.

**This is a hypothesis, not a result — two earlier ones were refuted, so treat it accordingly.**
It is cheap to test on the Linux box, and that test is the next step. **A full runbook for
continuing on the Linux boot is in [`NEXT_ON_LINUX.md`](NEXT_ON_LINUX.md)** — including the
`epsCG` decomposition to repeat there (which says *which* term of `T = C + k·iters` differs, and
is more diagnostic than the THP test alone) and a `perf` recipe, since Linux can profile what
gprof could not on MinGW.

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled          # likely [always] or [madvise]
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
./run_benchmark.sh                                        # re-run the 1-rank PIC point
```

If Linux's block-Jacobi time rises from ~24 s toward the Windows ~37 s with THP off, it is
confirmed. Also still worth one cheap check there:
`grep '^CC_FLAGS' $PETSC_DIR/lib/petsc/conf/petscvariables` — `/home/alopp/petsc/3.24.5` was
hand-built and its `COPTFLAGS` were never recorded; if it is also `-O1`, the GAMG row was never
comparing like with like either.

The **DSMC** rows are unaffected by all of this (no PETSc) and remain a clean OS comparison.

Raw data: `results/linux_timings.csv`. Regenerate the comparison with
`python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv`.
