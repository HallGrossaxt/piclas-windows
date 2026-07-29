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
- **Multi-rank DSMC is the one place Windows edges ahead** (~1.07–1.09x) — the MPI-vendor
  variable (OpenMPI 4.1.1 vs MS-MPI); Linux parEff 71% vs 78% at 6 ranks.
- Since it's the **same CPU (dual boot)**, hardware is excluded. But that does **not** make
  these numbers pure "OS" effects — see the next section: at least part of the PIC gap is a
  **build asymmetry on our side**, not a property of Windows.

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

**Status: unmeasured.** The decisive test is a PETSc rebuild with
`COPTFLAGS='-O3 -march=native'` into a separate prefix, then relink and re-run the 1-rank PIC
point. Until that is done, treat the PIC row as **not** a clean OS-vs-OS comparison:
`/home/alopp/petsc/3.24.5` on the Linux side was hand-built and its `COPTFLAGS` were never
recorded, so the PIC numbers may be comparing an `-O1` PETSc against an optimised one. The
**DSMC** rows are unaffected by all of this (no PETSc) and remain a clean OS comparison.

Raw data: `results/linux_timings.csv`. Regenerate the comparison with
`python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv`.
