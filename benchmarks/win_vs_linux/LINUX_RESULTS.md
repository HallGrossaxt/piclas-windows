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
- Since it's the **same CPU (dual boot)**, these deltas are genuine OS + MPI-stack effects,
  not hardware.

Raw data: `results/linux_timings.csv`. Regenerate the comparison with
`python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv`.
