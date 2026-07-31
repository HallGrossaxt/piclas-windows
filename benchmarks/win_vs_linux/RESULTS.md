# Results — Windows (MS-MPI) baseline

Machine: Windows 11, 10 physical cores / 16 logical. MS-MPI (`mpiexec -n`).
Binaries: PIC = `build-poisson-boris-petsc-mpi` (PETSc 3.24.5, `-march=native`);
DSMC = `build-maxwell-dsmc-release-mpi` (`-march=x86-64-v2`). Release, both MPI=ON.
Wall time = PICLas' own `PICLAS FINISHED! [ … sec ]` (pure solve). Raw data: `results/win_timings.csv`.

> **⚠️ Read [the fixed-configuration sweep](#fixed-configuration-sweep-2026-07-30-current-numbers)
> at the bottom first — it supersedes the single-run tables below.** They were taken before the
> OpenBLAS-threading and PETSc-`-O3` fixes and at one run per point, on a box with 3–6% drift.

## PIC — HDG-Poisson HEMP thruster (2000 steps)

| ranks | block-Jacobi [s] | GAMG [s] | GAMG speedup |
|------:|-----------------:|---------:|-------------:|
| 1 | 36.30 | 44.70 | 0.81× |
| 2 | 23.52 | 21.22 | 1.11× |
| 4 | 16.38 | 13.72 | 1.19× |
| 6 | 15.05 | 12.28 | 1.23× |

Strong scaling (speedup vs 1 rank / parallel efficiency):

| ranks | block-Jacobi | GAMG |
|------:|-------------:|-----:|
| 1 | 1.00× (100%) | 1.00× (100%) |
| 2 | 1.54× (77%)  | 2.11× (105%) |
| 4 | 2.22× (55%)  | 3.26× (81%)  |
| 6 | 2.41× (40%)  | 3.64× (61%)  |

**GAMG story.** Serial, GAMG is *slower* (0.81×): building the multigrid hierarchy costs
more than the ~19-vs-36 iteration saving buys back on a single-domain 1275-element problem.
In parallel the picture flips — block-Jacobi weakens as the domain is split into more
subdomains (its iteration count climbs), while GAMG stays robust, so GAMG pulls ahead and the
gap widens with rank count (1.23× at 6 ranks and still growing). GAMG also scales markedly
better (3.64× vs 2.41× at 6 ranks; superlinear 2.11× at 2 ranks from cache effects).

## DSMC — fully-periodic 3D box (27000 elems, 810k particles, 1000 steps, triatracking)

| ranks | time [s] | speedup | parEff |
|------:|---------:|--------:|-------:|
| 1 | 397.77 | 1.00× | 100% |
| 2 | 197.55 | 2.01× | 101% |
| 4 | 111.73 | 3.56× |  89% |
| 6 |  85.52 | 4.65× |  78% |

A proper strong-scaling curve: monotonic speedup to 6 ranks with efficiency decaying
gracefully (78% at 6 ranks), superlinear at 2 ranks (cache). This is the **enlarged** case —
30³ elements, 810k particles filling the full box uniformly, 1000 steps — sized so the time
loop dominates the one-time init and each rank has enough work (~4500 elems / 135k particles
at 6 ranks) to hide MPI overhead.

> The original small case (3375 elems, 1e5 particles in a quarter-box, 200 steps) gave
> 15.3 s → 7.9 s (2 ranks, 1.93×) then **regressed** at 4/6 ranks — past 2 ranks the fixed
> costs dominated the short solve. Kept here only as a note; the numbers above are the real curve.

## Linux comparison
Done — see **[`LINUX_RESULTS.md`](LINUX_RESULTS.md)** for the OS-vs-OS numbers (same physical
machine, dual boot, PICLas 4.2.0 + the GAMG patch on GCC 11.2 / OpenMPI 4.1.1).

> ⚠️ **The PIC numbers in the table above are obsolete as an OS comparison, and the table's
> 1-rank point is the worst affected.** Two build asymmetries, both on our side, were found and
> fixed. Neither is a property of Windows:
>
> 1. **Multithreaded OpenBLAS** (the big one, **1-rank only**). MSYS2's OpenBLAS spawns a thread
>    team per `daxpy`, and PETSc calls it ~110k times per run; Ubuntu's reference netlib BLAS is
>    single-threaded. `OPENBLAS_NUM_THREADS=1` takes the 1-rank block-Jacobi point from
>    **36.70 s to 27.26 s** against Linux's flag-matched 27.47 s — **parity**. Within noise by
>    2 ranks, gone by 4.
> 2. **PETSc built `-g -O`** (i.e. -O1, generic) on Windows against `-O3 -march=native` on Linux.
>    Worth 3.2–3.6% on Windows, 11.4% on Linux.
>
> With both equalised, PIC at 1 rank is **0.99×** — the once-headline "0.66× block-Jacobi" was
> our own configuration. The DSMC rows link no PETSc, never hit this, and were at parity all
> along. Full account: `LINUX_RESULTS.md` → "Windows-side session, 2026-07-30".
>
> The **GAMG-vs-block-Jacobi** columns above are same-session ratios and remain valid.
> Re-running the sweep with `OPENBLAS_NUM_THREADS=1` and the `-o3petsc` binary would refresh the
> absolute PIC numbers; it has not been done.

Also note: "Windows edges ahead on multi-rank DSMC (~1.07–1.09×)" **did not reproduce** — see the
Repeatability section in `LINUX_RESULTS.md`. Treat it as a tie within scatter.

Regenerate that table with

```bash
python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv
```

---

# Fixed-configuration sweep, 2026-07-30 (current numbers)

**These supersede every table above.** `sweep_repeats_win.sh`, **3+ repeats per point, medians**,
with both build fixes applied: the **`-o3petsc` PIC binary** and **`OPENBLAS_NUM_THREADS=1`**.
Raw data with every repetition: `results/win_timings_fixed_raw.csv`; medians:
`results/win_timings_fixed.csv`.

## PIC — HDG-Poisson HEMP thruster (2000 steps)

| ranks | block-Jacobi [s] | GAMG [s] | GAMG speedup | old BJ | old GAMG |
|------:|-----------------:|---------:|-------------:|-------:|---------:|
| 1 | **27.09** | **34.97** | 0.77× | 36.30 | 44.70 |
| 2 | 22.77 | 20.38 | 1.12× | 23.52 | 21.22 |
| 4 | 16.03 | 14.02 | 1.14× | 16.38 | 13.72 |
| 6 | 15.19 | 12.56 | 1.21× | 15.05 | 12.28 |

Repeat spread 1–3% (against 3–6% for the old single runs). The **1-rank points drop 25% / 22%**;
everything from 2 ranks up is unchanged, exactly as the OpenBLAS diagnosis predicts — see
`LINUX_RESULTS.md` → "Windows-side session", Step 5.

Strong scaling (speedup vs 1 rank / parallel efficiency):

| ranks | block-Jacobi | GAMG |
|------:|-------------:|-----:|
| 1 | 1.00× (100%) | 1.00× (100%) |
| 2 | 1.19× (59%)  | 1.72× (86%) |
| 4 | 1.69× (42%)  | 2.49× (62%) |
| 6 | 1.78× (30%)  | 2.78× (46%) |

> **PIC scaling now looks *worse* than the old table (BJ 1.78× vs 2.41× at 6 ranks). That is a
> correction, not a regression.** The old 1-rank baseline was inflated by the OpenBLAS thread-team
> penalty, which flattered every speedup measured against it. The absolute times at 2/4/6 ranks are
> unchanged; only the reference point moved. The real lesson is that this 1275-element case simply
> does not have enough work to scale past ~4 ranks.

The **GAMG-vs-block-Jacobi** ratios are essentially identical to before
(0.77/1.12/1.14/1.21 vs 0.81/1.11/1.19/1.23) — as expected, since those were always
same-session ratios, where drift cancels.

## DSMC — fully-periodic 3D box (27000 elems, 810k particles, 1000 steps, triatracking)

| ranks | time [s] | reps | spread | speedup | parEff | July |
|------:|---------:|-----:|-------:|--------:|-------:|-----:|
| 1 | 404.79 | 3 | 0.03% | 1.00× | 100% | 397.77 |
| 2 | 204.24 | 3 | 1.2% | 1.98× | 99% | 197.55 |
| 4 | 123.04 | 6 | 24% ⚠️ | 3.29× | 82% | 111.73 |
| 6 | 109.73 | 5 | 1.6% | 3.69× | 61% | 85.52 |

DSMC links no PETSc, has **no OpenMP** (checked: no `GOMP_`/`omp_get` symbols) and does not call
BLAS in its hot path, so neither fix can touch it — and indeed 1 and 2 ranks reproduce July to
within 2%.

> **⚠️ The 6-rank DSMC point has degraded across sessions on this machine, and it is not a code
> change.** Same binary, same inputs: **85.52 s (Jul 28) → 97.94 s (Jul 29) → 109.73 s (Jul 30)**,
> roughly −13% per session, while 1-rank moved only +1.8%. The 6-rank spread *within* today's
> session is only 1.6% (n=5), so this is reproducible now — it is the machine's all-core behaviour
> that has changed, not measurement noise. Thermal state is the obvious suspect. **Treat
> high-rank-count absolute times on this box as untrustworthy across days**, and do not read the
> declining parallel efficiency (78% → 61%) as a property of PICLas.
>
> The 4-rank point also produced one clear outlier (143.14 s against a 115–127 s cluster), which
> is why it carries 6 repeats.
