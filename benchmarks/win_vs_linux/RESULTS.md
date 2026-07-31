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

> ## ⚠️ These DSMC multi-rank numbers are thermally throttled — read this before quoting them
>
> An earlier version of this file claimed the box had "degraded ~13% per session" at 6 ranks
> (85.52 s Jul 28 → 97.94 Jul 29 → 109.73 Jul 30). **That was wrong and is retracted.** The real
> effect is **within-session thermal throttling under sustained all-core load.** Five consecutive
> identical 6-rank DSMC runs, same binary, same inputs, back to back:
>
> | run | 1 | 2 | 3 | 4 | 5 |
> |---|---:|---:|---:|---:|---:|
> | sec | 88.24 | 91.78 | 92.31 | 105.16 | 109.05 |
>
> A monotonic **+24% in five runs.** That single trend explains everything the "degradation"
> story was invented for: the sweep above runs DSMC **last**, so its 6-rank point (109.73 s) is
> the fully-heated value and coincides with run 5; July's 85.52 s is a cold-start value and
> coincides with run 1. Nothing about the machine changed between days — only how much load
> preceded the measurement.
>
> Consequences, which apply to any future benchmarking on this box:
>
> - **The DSMC 4- and 6-rank rows above are hot-state numbers.** Cold-state 6-rank is ~88 s. The
>   4-rank outlier (143.14 s against a 115–127 s cluster) is the same effect, not a glitch.
> - **Parallel efficiency at 4/6 ranks is understated** and must not be read as a property of
>   PICLas. The 1- and 2-rank rows are unaffected (short enough, fewer cores) and reproduce to
>   0.03% / 1.2%.
> - **Never compare two arms in a fixed order.** The second one is the hot one. Interleave with
>   **ABBA ordering** (see `gpu_ab_win.sh`), which cancels a linear thermal trend; a fixed A-then-B
>   order manufactures a 5–20% difference out of nothing.
> - The previously documented "±15% drift at 6 ranks" is very likely this same effect rather than
>   independent session noise.

---

# GPU support: measured, and it is a 4–14% **loss** on this benchmark

`gpu_ab_win.sh`, ABBA-ordered with cooldowns, 2 repetitions per arm per rank count, medians.
Raw data: `results/win_timings_gpu_raw.csv`. GPU is an **RTX 3060** (12 GB, compute 8.6,
driver 591.86).

## DSMC — the only case that can be measured

`build-maxwell-dsmc-release-mpi` vs `build-maxwell-dsmc-release-mpi-gpu` differ in **exactly one
CMake option** (`PICLAS_USE_GPU`) and agree on eqnsys, timedisc, `LIBS_USE_PETSC=OFF`, Release and
`-march=x86-64-v2 -mtune=generic`. A clean single-variable A/B.

| ranks | CPU [s] | GPU [s] | **speedup** | GPU util | VRAM |
|------:|--------:|--------:|------------:|---------:|-----:|
| 1 | 412.51 | 442.94 | **0.93×** | 0 % | 870 MiB |
| 2 | 202.73 | 230.00 | **0.88×** | 1 % | 1156 MiB |
| 4 | 125.74 | 130.43 | **0.96×** | 6 % | 1706 MiB |
| 6 |  97.45 | 111.31 | **0.88×** | 6 % | 2264 MiB |

**The GPU build is slower at every rank count**, and the losses are paired and repeatable — in
every one of the eight pairs the GPU arm was the slower one, including the reps where the GPU ran
*first* (i.e. on the cooler machine), so this is not the thermal ordering artefact.

**GPU utilisation of 0–6% is the whole story.** The device is idle almost the entire run.

### Why — and why this is not a tuning problem

PICLas' CUDA support offloads the **particle push** (`particle_push.cu`; `lserk_push.cu` for the
field-coupled PIC push). **Collision, pairing, tracking, sampling and the field solve all stay on
the CPU.** So every timestep pays a host→device→host copy of particle state to run one cheap
kernel, while the expensive stages never leave the CPU. This case is dominated by **tracking**,
which is the hardest PICLas stage to port (per-particle ray/cell-face intersection, mesh
connectivity, mortar, halo, MPI).

Independent corroboration from the AgNozzle study: there the push measured ~14% of runtime in the
GPU build versus ~2–4% on CPU — i.e. moving the push to the GPU made the push *itself* more
expensive, exactly the transfer overhead seen here.

At 1 rank the GPU is uncontended and still 0.93×, so single-GPU sharing across ranks is **not**
the explanation either (though the binary does warn that VRAM is partitioned per rank and
suggests NVIDIA MPS for many-rank runs).

## PIC — cannot be measured without a new build

Every GPU build on this machine is `LIBS_USE_PETSC=OFF`, so none can run the benchmark's
`PrecondType=2/4` PETSc solvers (without PETSc, `PrecondType` selects the internal-CG
preconditioner and GAMG is unavailable). `build-poisson-boris-mpi-gpu` also lacks superB and
aborts immediately on the frozen background field:

```
init_BGField.f90:422   'Activate SuperB.'
```

A number would need a fresh build with `PICLAS_USE_GPU=ON` + `POSTI_BUILD_SUPERB=ON` +
`LIBS_USE_PETSC=ON` at `-march=native`. **Expect ~1.00× from it**: this case carries only ~12
particles and ~94% of its runtime is the HDG field solve, which stays on the CPU. There is
essentially no push to offload.

## Verdict

**Do not use the GPU builds for this class of work.** On DSMC they cost 4–14%; on the PIC case
they cannot run at all, and would be neutral if they could. A GPU port only pays here once the
**collision** stage (dense/collision-dominated regimes) or **tracking** is on the device — see the
AgNozzle Phase-0 measurement, which put the Amdahl ceiling for a GPU collision kernel at ~1.03×
in the rarefied regime.
