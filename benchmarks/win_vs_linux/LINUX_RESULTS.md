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
  > **Corrected 2026-07-30 (Linux side):** this is *not* symmetric. The Linux PETSc reports
  > `BLASLAPACK_LIB = -llapack -lblas`, and `libblas.so.3` resolves through the Debian
  > alternatives system to `/usr/lib/x86_64-linux-gnu/blas/libblas.so.3.12.0` — Ubuntu's
  > **reference netlib BLAS** (`libblas3`). No OpenBLAS is installed on the Linux side at all.
  > So Windows has the *faster* BLAS of the two, and Linux still wins by 1.8x. BLAS is ~12% of
  > the Linux profile (`dgemv`/`dsymv`/`ddot`/`daxpy`, called from PICLas' HDG Fortran, not from
  > PETSc's sparse kernels), so installing OpenBLAS on Linux is a real but separate ~few-%
  > opportunity — it cannot explain anything about the gap, it only understates Linux.
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

### Conclusion at the end of the Windows session (superseded — kept for the record)

The gap is **inside PETSc's sparse CG kernels**, executing identical work on identical silicon.
That was read as consistent with `-O3` buying only 1.6%: sparse MatMult is memory-bound, not
compute-bound, so optimisation level barely moves it. The leading explanation was therefore the
**memory subsystem**, most plausibly **transparent huge pages**.

**Both halves of that reading turned out to be wrong** — the kernels are not memory-bound, and
huge pages are worth ~2%. See the next section, measured on the Linux boot.

---

# Linux-side session, 2026-07-30 — the four open steps, executed

Everything below is 1 rank, `PrecondType=2` (block-Jacobi), the frozen `.h5` inputs, on the same
i5-13400F. Scripts committed alongside: `decomp_linux.sh`, `thp_linux.sh`, `thpon.c`,
`build_petsc_o1.sh`.

## Step 1 — PETSc build flags: the comparison was never fair

```
Linux   CC_FLAGS = -fPIC -Wall -Wwrite-strings -Wno-unknown-pragmas -Wno-lto-type-mismatch
                   -Wno-stringop-overflow -fstack-protector -fvisibility=hidden
                   -O3 -march=native -mtune=native
Windows CC_FLAGS = ... -fvisibility=hidden -g -O
```

Recorded permanently, as asked. The Linux PETSc **is** `-O3 -march=native`, so the PIC rows in the
tables above were **`-O1` generic (Windows) vs `-O3 -march=native` (Linux)** all along. The fair
Windows baseline is the already-measured `petsc-msmpi-O3` build (37.05 s block-Jacobi,
40.47 s GAMG), i.e. block-Jacobi **0.65x** and GAMG **0.84x**, not 0.66x/0.76x.

Original configure line recovered from
`petsc/src/petsc-3.24.5/arch-linux-c-opt/lib/petsc/conf/reconfigure-arch-linux-c-opt.py`.

## Step 2 — the `epsCG` decomposition: the gap is entirely the per-iteration slope

Iteration counts match Windows almost exactly, so both OSes really are doing the same work:

| `epsCG` | avg iters (Linux) | avg iters (Win) | Linux time | Windows time |
|---|---:|---:|---:|---:|
| 1e-1 | 2.00 | 2.1 | 8.27 s | 11.42 s |
| 1e-3 | 8.90 | 8.5 | 16.68 s | 25.45 s |
| 5e-5 (benchmark) | 15.50 | 15.5 | 24.19 s | 40.01 s |
| `HDGSkip=100` | — | — | 1.26 s | 2.27 s |

Fitting `T = C + k·iters` on the outer two points, and validating on the middle one:

| | fixed cost `C` | slope `k` | mid predicted | mid measured | error |
|---|---:|---:|---:|---:|---:|
| **Linux** | **5.91 s** | **1.179 s/iter** | 16.41 s | 16.68 s | −1.6% |
| **Windows** | 6.94 s | 2.134 s/iter | 25.07 s | 25.45 s | −1.5% |

The model holds equally well on both sides. Splitting the benchmark point into three buckets:

| bucket | Windows | Linux | win/linux |
|---|---:|---:|---:|
| non-solve (push, tracking, interpolation, I/O) | 2.27 s | 1.26 s | 1.80x |
| **fixed per-solve HDG Fortran** (assembly, trace post-processing) | **4.67 s** | **4.65 s** | **1.00x** |
| **iteration-proportional CG work** | **33.07 s** | **18.28 s** | **1.81x** |

This is the single most informative result of the session, and it **refutes the previous
section's closing guess** that "by elimination the remaining ~13 s sits in PICLas' own Fortran on
the Windows toolchain". PICLas' HDG assembly Fortran is at **exact parity** — 4.67 s vs 4.65 s.
MinGW codegen, the Win64 ABI and UCRT `malloc` are therefore all off the hook for the headline
number: they demonstrably do not slow down the one bucket that is pure PICLas Fortran.

The whole gap lives in the **per-CG-iteration** term, 1.81x. (The 1.80x on the small non-solve
bucket is a separate, ~1 s effect — most of that bucket is HDF5 output, where a Windows
filesystem penalty is unsurprising and irrelevant at this size.)

## Step 3 — transparent huge pages: refuted (third strike)

Two things had to be fixed before this test meant anything, and both are traps worth recording:

1. **THP on this box is `[madvise]`, not `[always]`.** glibc's `malloc` never calls
   `madvise(MADV_HUGEPAGE)` on its own, so the *default* Linux run already has PETSc's heap on
   **4 KB pages — the same page size as Windows.** Setting THP to `never`, as the runbook
   proposed, would therefore have measured nothing and produced a false "refuted".
   The informative direction is to turn huge pages **on**.
2. **The launching process had THP disabled by `prctl(PR_SET_THP_DISABLE)`**, which is inherited
   across `fork`/`exec` and makes both `MADV_HUGEPAGE` and glibc's
   `GLIBC_TUNABLES=glibc.malloc.hugetlb=1` **silently no-ops**. Confirmed by
   `awk '/^THP_enabled:/' /proc/<pid>/status` (`0` = disabled) and by `thp_fault_alloc` in
   `/proc/vmstat` staying at 0. `thpon.c` clears the flag before `exec`.

With that sorted — interleaved base/huge pairs so drift cancels, `thp_fault_alloc` checked per run
to prove the "on" arm really got 2 MB pages:

| pair | 4 KB pages | 2 MB pages | THP faults (on-arm) |
|---|---:|---:|---:|
| 1 | 24.10 s | 23.73 s | 81 |
| 2 | 24.91 s | 24.55 s | 79 |
| 3 | 25.20 s | 24.42 s | 77 |

Median 24.91 s → 24.42 s: **~2%.** Huge pages are worth ~2%, against a gap of 1.81x. And the
Linux run that beats Windows by 1.81x is *itself on 4 KB pages*, so page size cannot be the
difference in the first place. **Refuted.**

## Step 4 — `perf`: not memory-bound, and squarely inside PETSc's C

`perf stat`, pinned to a P-core (`perf_event_paranoid` lowered to 1 via pkexec, restored to 4
afterwards). Raptor Lake is hybrid, so counters split into `cpu_core`/`cpu_atom`; the `cpu_core`
row is the run:

| counter | value | |
|---|---:|---|
| instructions / cycles | 378.0 G / 107.9 G | **IPC = 3.50** |
| dTLB-load-misses / dTLB-loads | 24.7 M / 133.6 G | **0.02%** |
| cache-misses / cache-references | 1.18 G / 8.17 G | 14.4% (refs are only 6% of loads) |

**IPC 3.50 is close to the core's issue width.** A memory-bound sparse kernel runs at IPC 0.5–1.0.
The dTLB miss rate is 0.02%. Both numbers independently kill the memory/TLB framing: this code is
**front-end/issue-bound — it is executing a very large number of instructions very efficiently.**
That matters, because instruction *count* is exactly what optimisation level controls.

`perf record` (flat, ≥0.8%):

| overhead | object | symbol |
|---:|---|---|
| 37.9% | libpetsc | `MatSolve_SeqSBAIJ_1_NaturalOrdering` |
| 26.2% | libpetsc | `MatMult_SeqSBAIJ_1_ushort` |
| 5.3% | libpiclas | `mod_hdg_linear::hdglinear` |
| 4.0% | libblas | `dgemv_` |
| 3.2% | libpiclas | `mod_elem_mat::postprocessgradienthdg` |
| 2.9% / 2.6% / 2.3% | libblas | `daxpy_` / `ddot_` / `dsymv_` |
| 1.9% | libpetsc | `VecAYPX_Seq` |

**64% of the entire run is two PETSc C functions.** Corroborated by `PETSC_OPTIONS=-log_view`
(saved to `results/logview_linux_bjacobi_1rank.txt`) — these are the numbers to compare against on
Windows:

| event | count | time | Mflop/s |
|---|---:|---:|---:|
| KSPSolve | 2000 | 18.03 s (76%) | 4869 |
| MatSolve (ICC triangular solve, = PCApply) | 31021 | 9.47 s (40%) | 4014 |
| MatMult | 33020 | 6.37 s (27%) | 6352 |
| MatCholFctrNum + MatICCFactorSym | 1 + 1 | 0.004 s | — |

`log_view` is a far better instrument than wall clock for the remaining question: `Count` and
`Flop` are algorithmic and must match across OSes, so the **Mflop/s column is a drift-free,
single-run, per-kernel speed comparison.** Run it on Windows and the gap is localised exactly.

## The new tension — and what it points at

Two established facts do not fit together:

- 64% of the run is inside PETSc's compiled C, and that code is **issue-bound** (IPC 3.5), the
  regime where `-O1` vs `-O3 -march=native` should matter a great deal;
- yet rebuilding the **Windows** PETSc at `-O3 -march=native` moved block-Jacobi by only **1.6%**.

Those cannot both be true of a working experiment. The most likely explanation is that the
**Windows `-O3` relink never took effect at runtime**: on Windows, DLLs resolve by search order,
so PICLas can link against the `petsc-msmpi-O3` import library and still load the *old* `-O1`
`libpetsc` DLL from `PATH`. That would produce exactly the observed 1.6% (i.e. noise).

**This is now the prime suspect and it is directly checkable on the Windows boot** — see
[`NEXT_ON_WINDOWS.md`](NEXT_ON_WINDOWS.md) §2. The Linux-side half of the same question is
reported immediately below.

## Step 5 — PETSc `-O1` vs `-O3` measured on Linux: worth 11.4%, and Windows' 1.6% is wrong

`build_petsc_o1.sh` built a second PETSc 3.24.5 from the same source with the **Windows** flags —
`--with-debugging=0` and no `COPTFLAGS`, which yields exactly the Windows string:

```
Linux -O1 mirror  CC_FLAGS = ... -fvisibility=hidden -g -O      <- identical to Windows
```

Generic arch on both, so `-march` is matched too, not just the `-O` level. The soname is unchanged
(`libpetsc.so.3.24`), so **PICLas needed no rebuild** — `LD_LIBRARY_PATH` order alone selects which
library loads, and the script prints the resolved path per arm to prove the swap took (which is the
whole point, given what is suspected on the Windows side).

| pair | PETSc `-O3 -march=native` | PETSc `-g -O` (Windows flags) |
|---|---:|---:|
| 1 | 24.11 s | 26.81 s |
| 2 | 25.39 s | 27.47 s |
| 3 | 24.65 s | 27.99 s |
| **median** | **24.65 s** | **27.47 s** |

**PETSc's optimisation level is worth 11.4% on Linux** — and per kernel (`log_view`, saved as
`results/logview_linux_bjacobi_1rank_petscO1.txt`), the effect lands where the IPC reading said it
would:

| event | Mflop/s at `-O3` | Mflop/s at `-g -O` | `-O3` advantage |
|---|---:|---:|---:|
| MatMult | 6352 | 4901 | **1.30x** |
| MatSolve (ICC triangular solve) | 4014 | 3722 | 1.08x |
| KSPSolve (composite) | 4869 | 4233 | 1.15x |

`MatMult` gains 30% from optimisation — it is a vectorisable streaming kernel. `MatSolve` gains
only 8%: a triangular solve is a serial dependency chain, so it is latency-bound and optimisation
cannot help much. Since `MatSolve` is the larger consumer (40% of runtime vs 27%), the composite
lands at 11.4%.

### Two consequences

**1. The Windows `-O3` measurement of 1.6% does not hold up.** Linux gets 11.4% from the identical
swap on the identical source. `MatMult` alone is 27% of the run and speeds up 1.30x, which is worth
~6 points on its own — 1.6% is not a plausible total. The DLL-search-order explanation above is the
obvious candidate and should be checked before anything else on Windows.

**2. Re-baselined, with PETSc's optimisation level equalised:**

| comparison | Windows | Linux | ratio |
|---|---:|---:|---:|
| as originally reported (`-O1` vs `-O3`) | 37.67 s | 24.65 s | 1.53x |
| **both at `-g -O` generic — fair** | **37.67 s** | **27.47 s** | **1.37x** |
| both nominally `-O3` (Windows number suspect) | 37.05 s | 24.65 s | 1.50x |

Equalising PETSc's build flags removes **30% of the excess** (1.53x → 1.37x). So the unfair
comparison was a real contributor, but it is not the whole story either.

### Where the investigation now stands

**Explained:** ~30% of the PIC gap is our own build asymmetry — the Windows PETSc is `-O1`
generic, the Linux one `-O3 -march=native`. Fixing it on Windows is worth ~11% and is a genuine
production improvement, unlike the two flags tested before it (`-fstack-arrays` 3%, and the earlier
`-O3` claim of 1.6% which now looks like a botched experiment).

**Still open:** a **1.37x** residual, now much better characterised than at the start of the
session. It is:

- **not** memory bandwidth, TLB pressure or page size — IPC 3.5, dTLB miss 0.02%, huge pages ~2%;
- **not** PICLas' Fortran — the pure-Fortran HDG assembly bucket is at exact parity (4.67 / 4.65 s);
- **not** BLAS — Windows has OpenBLAS, Linux only reference netlib BLAS, i.e. the wrong way round;
- **not** MPI, algorithm, or iteration count — 1 rank, and iteration counts match exactly;
- **not** PETSc's optimisation level or target arch — now equalised, and 1.37x survives it.

What is left is narrow and concrete: **the same two PETSc C functions, from the same source, with
the same flags, compiled by MinGW GCC 15.2 for Windows versus GCC 11.2 for Linux, run 1.37x
apart.** That is a codegen/ABI/C-runtime question about `MatSolve_SeqSBAIJ_1_NaturalOrdering` and
`MatMult_SeqSBAIJ_1_ushort`, and it is answerable by disassembling those two functions on both
sides — no more whole-program experiments needed. Note the GCC major-version difference is now a
live variable again (it was previously dismissed on the grounds that the newer compiler was on the
slower side, which is weak reasoning once the hot code is this localised).

The **DSMC** rows are unaffected by all of this (no PETSc) and remain a clean OS comparison.

Raw data: `results/linux_timings.csv`. Regenerate the comparison with
`python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv`.

---

# Windows-side session, 2026-07-30 — ✅ RESOLVED: it was multithreaded OpenBLAS

The 1.37x residual is **explained and fixable**. One environment variable —
`OPENBLAS_NUM_THREADS=1` — takes the 1-rank block-Jacobi PIC case from **36.70 s to 27.26 s**
against Linux's 27.47 s, i.e. **parity**. Nothing about Windows, MinGW, MS-MPI or the Win64 ABI
was ever the problem.

Scripts: `blas_threads_win.sh` (the decisive test), `petsc_opt_ab_win.sh` (the `-O3` re-measure),
`logview_win.sh` (the instrument). Raw evidence: the three `results/logview_win_*.txt` files.

## Step 1 — the `-O3` measurement was fine; the DLL hypothesis was impossible

`NEXT_ON_WINDOWS.md` §2 guessed that PICLas linked `petsc-msmpi-O3`'s import library but loaded
the old `-O1` `libpetsc` DLL from `PATH`. **That cannot happen here: the Windows PETSc is a static
`libpetsc.a`** (130 MB at `-g -O`, 45 MB at `-O3`), so the choice is made at link time and baked
into `libpiclas.dll`. Verified three ways rather than by process inspection:

| check | result |
|---|---|
| `CMakeCache.txt` of each build | `PETSC_LIBDIR` = `petsc-msmpi/lib` vs `petsc-msmpi-O3/lib` |
| `CC_FLAGS` of each install | `… -g -O` vs `… -O3 -march=native -mtune=native` |
| `objdump` of the hot kernels out of each `libpetsc.a` | genuinely different code — see Step 3 |

Re-measured properly (interleaved, 7 pairs across two rounds, `PrecondType=2`, 1 rank):

| | PETSc `-g -O` | PETSc `-O3 -march=native` |
|---|---|---|
| runs | 37.89 / 39.19 / 37.81 / 37.35 / 37.80 / 38.69 / 36.97 | 35.76 / 36.25 / 37.65 / 37.21 / 36.49 / 36.22 / 36.70 |
| **median** | **37.81 s** | **36.49 s** |

**3.6%**, and roughly a third of that is not speed at all: the `-O3` build averages **15.30**
CG iterations against **15.50** (FMA contraction changes the rounding, hence the convergence path),
worth ~0.4 s by the `k = 2.13 s/iter` fit. So ~2.4% is real kernel speed.

**The original 1.6% was noise, not a botched experiment**, and Linux's 11.4% simply does not
transfer — Step 2 says why. The paired spread was wide (0.14 s to 2.94 s per pair), which is
exactly why a single run gave 1.6% and another would have given 8%.

## Step 2 — `-log_view` on Windows: the blamed kernels are innocent

This is the whole answer. `Count` and `Flop` match Linux, so the Mflop/s column is a drift-free
per-kernel speed comparison. Windows `-g -O` against the flag-matched
`results/logview_linux_bjacobi_1rank_petscO1.txt`:

| kernel | calls | Windows `-O1` | Linux `-O1` | verdict |
|---|---:|---:|---:|---|
| MatMult | 33.5k | 7.69 s / **5338** Mflop/s | 8.23 s / 4901 | **Windows 1.09x faster** |
| MatSolve (ICC solve = PCApply) | 31.5k | 10.18 s / **3793** | 10.19 s / 3722 | **parity** |
| **VecAXPY** | **110k** | **6.03 s / 575** | **0.44 s / 7646** | **13.6x slower** |
| VecNorm | 2.0k | 0.122 s / 515 | 0.017 s / 3619 | 7.0x slower |
| VecAYPX | 104k | 0.851 s / 3812 | — | — |
| KSPSolve (composite) | 2000 | 29.98 s / 2976 | 20.70 s / 4233 | 1.42x |

**`MatSolve_SeqSBAIJ_1_NaturalOrdering` and `MatMult_SeqSBAIJ_1_ushort` — the 64% of runtime that
the Linux `perf` profile pointed at, and the entire subject of `NEXT_ON_WINDOWS.md` §4 — are at or
better than parity on Windows.** The gap is in PETSc's BLAS-1 calls.

Per call: VecAXPY **54.7 µs** on Windows vs **4.1 µs** on Linux; VecNorm **61 µs** vs 8.7 µs. A
*fixed* ~50 µs regardless of vector length is not slow arithmetic — it is a thread-team wakeup.

And there is a control **inside the same Windows run** that settles it without involving Linux at
all: `VecAYPX` performs the same shape of work on the same vectors, 104k times, but PETSc
implements it in its own C rather than calling BLAS. It costs **8.1 µs/call**. `VecAXPY` routes to
`BLASaxpy` and costs **54.7 µs/call**. Same operation, same data, ~46 µs of pure call overhead.

## Step 3 — disassembly: real differences, but not the ones that mattered

Done anyway, since `NEXT_ON_WINDOWS.md` §4 asked for it. `MatMult_SeqSBAIJ_1_ushort` inner loop:

| | instructions/element | FP ops | base pointers |
|---|---:|---|---|
| Windows `-g -O` | **12** | `mulsd` + `addsd` | **spilled — reloaded from `(%rsp)` every element** |
| Windows `-O3 -march=native` | **8** | 2x `vfmadd` | held in `%r11` / `%rbp` |

`MatSolve`'s forward-solve loop goes from `mulsd`/`addsd`/`movsd` to a single `vfmadd213sd`, with no
spills at either level. Whole-function counts: MatMult 206→190, MatSolve 210→152 instructions.

So the `-O1` codegen really is 1.5x fatter per element — but this is a **dead end for the gap**,
because Windows `-O1` MatMult already *beats* Linux `-O1` MatMult (5338 vs 4901 Mflop/s). GCC 15.2
is not producing worse code than GCC 11.2 at matched flags. The instruction-count difference is
also why `-O3` should have helped more than 3.6%, and Step 2 explains why it did not: 16% of the
runtime sat in OpenBLAS, where PETSc's optimisation level has no reach (VecAXPY 575 → 565 Mflop/s).

## Step 4 — the cause: MSYS2's OpenBLAS is multithreaded

`BLASLAPACK_LIB = -Wl,-rpath,/ucrt64/lib -L/ucrt64/lib -lopenblas`. MSYS2 ships OpenBLAS built
with threading enabled; the box has 16 logical cores. PETSc calls `BLASaxpy` 110k times on vectors
of ~15.7k doubles, and OpenBLAS's threshold for going parallel on `daxpy` sits just below that, so
it forks and joins a thread team **110,000 times** to do ~31 kflop of work each time. Ubuntu's
reference netlib BLAS on the Linux side is single-threaded and never pays it — which is why Linux
wins *despite* having the objectively worse BLAS library.

`OPENBLAS_NUM_THREADS=1`, drift-free per kernel
(`results/logview_win_bjacobi_1rank_blas1thread.txt`):

| kernel | Win default | Win **1 BLAS thread** | Linux `-O1` |
|---|---:|---:|---:|
| VecAXPY | 6.03 s / 575 | **0.431 s / 7885** | 0.443 s / 7646 |
| VecNorm | 0.122 s / 515 | **0.010 s / 6073** | 0.017 s / 3619 |
| KSPSolve | 29.98 s / 2976 | **20.22 s / 4341** | 20.70 s / 4233 |

Both BLAS-1 rows end up **faster than Linux**, as they should — OpenBLAS is the better library once
it stops synchronising. And wall clock, interleaved so drift cancels:

| pair | default OpenBLAS | `OPENBLAS_NUM_THREADS=1` |
|---|---:|---:|
| 1 | 38.44 s | 27.26 s |
| 2 | 36.18 s | 26.89 s |
| 3 | 36.70 s | 27.70 s |
| **median** | **36.70 s** | **27.26 s** |

**1.35x — the entire 1.37x residual.** Against Linux's flag-matched 27.47 s that is **0.99x**.

## Step 5 — scope: it is a 1-rank effect, and it disappears on its own

The same interleaved A/B repeated at 2 and 4 ranks (medians of 3 pairs):

| ranks | default OpenBLAS | `OPENBLAS_NUM_THREADS=1` | ratio |
|---:|---:|---:|---:|
| **1** | 36.70 s | **27.26 s** | **1.35x** |
| 2 | 25.97 s | 25.65 s | 1.01x |
| 4 | 19.17 s | 18.80 s | 1.02x |

Gone by 2 ranks. The 4-rank `-log_view` with *default* OpenBLAS shows why — VecAXPY is already at
**24335 Mflop/s** (0.271 s over 209836 calls), with no overhead at all:

| kernel, 4 ranks, default OpenBLAS | time | Mflop/s |
|---|---:|---:|
| VecAXPY | 0.271 s | 24335 |
| VecAYPX | 0.451 s | 14140 |
| MatMult | 7.13 s | 10106 |
| MatSolve | 4.70 s | 12585 |

Domain decomposition shrinks each rank's vectors from ~15.7k to ~3.9k elements
(`Flop/Count`: 31.5 kflop → 7.9 kflop per call, at 2 flops per element), dropping them below
OpenBLAS's own parallelisation threshold — so it never spawns the team, and VecAXPY is back to
being *faster* than PETSc's hand-written VecAYPX, as a tuned BLAS should be. The threshold
therefore sits somewhere between ~3.9k and ~15.7k elements for `daxpy` in this build.

This retro-explains the shape of the original PIC table: `linux/win` was **0.66x at 1 rank** but
0.87/0.81/0.86x at 2/4/6. The extra ~20 points at 1 rank were the BLAS thread teams; what remains
at multi-rank is the PETSc `-O1`-vs-`-O3` asymmetry plus session drift.

## Step 6 — best Windows configuration, and the honest residual

With BLAS threading fixed, PETSc's optimisation level still earns its keep at 1 rank
(interleaved, 3 pairs, both arms `OPENBLAS_NUM_THREADS=1`):

| | PETSc `-g -O` | PETSc `-O3 -march=native` |
|---|---:|---:|
| runs | 28.07 / 28.62 / 28.21 | 27.99 / 27.19 / 27.34 |
| **median** | **28.21 s** | **27.34 s** (**3.2%**) |

**Recommended Windows PIC configuration: `petsc-msmpi-O3` + `OPENBLAS_NUM_THREADS=1`.**

The one genuine codegen difference left is drift-free from `log_view` and small: at `-O3`,
**MatMult** runs 5579 Mflop/s on Windows vs 6352 on Linux (**1.14x**), while MatSolve is at parity
(4038 vs 4014). GCC 11.2 vectorises that streaming kernel better for Linux than GCC 15.2 does for
MinGW — worth ~1 s on a 27 s run. That is the whole remaining story, and it is not worth chasing.

## Final scoreboard for the PIC 1-rank point

| configuration | Windows | Linux | ratio |
|---|---:|---:|---:|
| as originally reported (Win `-O1` / Linux `-O3`) | 37.67 s | 24.65 s | 1.53x |
| PETSc flags equalised at `-g -O` | 37.81 s | 27.47 s | 1.37x |
| **+ `OPENBLAS_NUM_THREADS=1`** | **27.26 s** | 27.47 s | **0.99x** |
| both sides' best (`-O3` PETSc; Win also 1 BLAS thread) | 27.34 s | 24.65 s | 1.11x |

> The last row still favours Linux by 11%, but Linux's `-O3` gain (11.4%) is larger than Windows'
> (3.2%) chiefly because MatMult vectorises better there. Also note Linux is still on reference
> netlib BLAS — installing OpenBLAS there (single-threaded!) would move its number too, so 1.11x
> is not a settled figure.

## What this means for the rest of the project

- **`OPENBLAS_NUM_THREADS=1` is worth setting for any serial or low-rank PICLas run on Windows
  that uses PETSc.** It is free, and at high rank counts it is a no-op.
- The **magnetron** work runs at MPI=4–6, so it is already past the threshold — do not expect this
  to move those numbers (same conclusion as the earlier `-O3` finding, for the same reason).
- This is the *third* time BLAS **call overhead** rather than BLAS arithmetic has dominated a
  piclas-win hot path — cf. the HDG CG MatVec, where a 4x4 `DGEMV` cost 94 ns against <2 ns
  inlined. On small problems, the cost of *calling* a tuned BLAS is the thing to measure first.
- The **DSMC** rows never linked PETSc, never called BLAS-1 in a loop, and were at parity
  throughout. They needed no correction, and that consistency is part of why this diagnosis holds.
