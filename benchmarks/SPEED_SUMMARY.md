# PICLas speed comparison — summary

Consolidated results of the Windows-vs-Linux benchmark and the optimisation work that came out of
it. Same physical machine throughout, dual boot, **Intel Core i5-13400F** (10 physical cores / 16
threads), so hardware is excluded by construction.

Detail lives in:
- [`win_vs_linux/RESULTS.md`](win_vs_linux/RESULTS.md) — Windows baselines, the fixed-configuration
  sweep, the GPU measurement and the thermal characterisation
- [`win_vs_linux/LINUX_RESULTS.md`](win_vs_linux/LINUX_RESULTS.md) — the OS comparison and the full
  investigation narrative
- [`hdg_matvec/README.md`](hdg_matvec/README.md) — the element-major HDG MatVec A/B

Relevant commits: `68c4960` (benchmark), `387d0ea` (root cause), `92da7bb` (fixed sweep),
`6c673b7` (GPU), `1451699` (the fix, in source), `e3fa5f0` (thermal), `f4f269a` (HDG MatVec).

---

## Headline: the Windows PIC penalty was ours, not the OS's

The benchmark opened with a large, unexplained Windows penalty on the PIC field solve. It
dissolved completely once two of our own build asymmetries were removed.

**1-rank PIC, block-Jacobi:**

| configuration | Windows | Linux | ratio |
|---|---:|---:|---:|
| as originally reported (Win PETSc `-O1` vs Linux `-O3`) | 37.67 s | 24.65 s | **1.53×** |
| PETSc flags equalised at `-g -O` | 37.81 s | 27.47 s | **1.37×** |
| **+ single-threaded BLAS** | **27.26 s** | 27.47 s | **0.99×** |
| both sides' best (`-O3` PETSc) | 27.34 s | 24.65 s | 1.11× |

---

## Full rank sweep

Windows = medians of 3+ repeats in the fixed configuration (`-o3petsc` binary, one BLAS thread).
Linux = single runs from 2026-07-28.

| case | ranks | Linux | Win (old) | **Win (fixed)** | linux/win old | **linux/win fixed** |
|---|---:|---:|---:|---:|---:|---:|
| PIC block-Jacobi | 1 | 23.99 | 36.30 | **27.09** | 0.66× | **0.89×** |
| | 2 | 20.45 | 23.52 | 22.77 | 0.87× | 0.90× |
| | 4 | 13.24 | 16.38 | 16.03 | 0.81× | 0.83× |
| | 6 | 12.95 | 15.05 | 15.19 | 0.86× | 0.85× |
| PIC GAMG | 1 | 33.98 | 44.70 | **34.97** | 0.76× | **0.97×** |
| | 2 | 18.47 | 21.22 | 20.38 | 0.87× | 0.91× |
| | 4 | 12.56 | 13.72 | 14.02 | 0.92× | 0.90× |
| | 6 | 10.02 | 12.28 | 12.56 | 0.82× | 0.80× |
| DSMC | 1 | 388.74 | 397.77 | 404.79 | 0.98× | 0.96× |
| | 2 | 210.61 | 197.55 | 204.24 | 1.07× | 1.03× |
| | 4 ⚠️ | 121.39 | 111.73 | 123.04 | 1.09× | 0.99× |
| | 6 ⚠️ | 91.27 | 85.52 | 109.73 | 1.07× | 0.83× |

The two 1-rank outliers are gone; what remains is a uniform **0.80–0.97 band**.
⚠️ = thermally contaminated, see [Caveats](#caveats-that-change-how-to-read-the-above).

---

## What each change was worth

| change | effect | scope |
|---|---:|---|
| **Single-threaded BLAS** | **1.35×** | 1 rank only; within noise by 2, gone by 4 |
| PETSc `-O3 -march=native` | 3.2–3.6% | 1 rank; ~0 at MPI≥4 |
| `-fstack-arrays` | 3% | tested, rejected as the explanation |
| Transparent huge pages | ~2% | refuted |
| **GPU (`PICLAS_USE_GPU=ON`)** | **0.88–0.96× — a loss** | DSMC; PIC cannot build |
| **Element-major HDG MatVec** | **1.85×** on s/iteration | internal CG (PETSc off) |

---

## Per-kernel comparison (`-log_view`) — the drift-free instrument

`Count` and `Flop` are algorithmic and identical across OSes, so the **Mflop/s column is a
single-run, drift-free, per-kernel speed comparison**. This is what actually found the bug, after
wall-clock experiments had chased the wrong two kernels for a day.

| kernel | Win `-O1` | Linux `-O1` | verdict |
|---|---:|---:|---|
| MatMult | **5338** | 4901 | Windows *faster* |
| MatSolve (ICC solve) | **3793** | 3722 | parity |
| **VecAXPY** | **575** | **7646** | **13.6× slower** |
| VecNorm | 515 | 3619 | 7.0× slower |
| KSPSolve (composite) | 2976 | 4233 | 1.42× |

`MatSolve_SeqSBAIJ_1_NaturalOrdering` and `MatMult_SeqSBAIJ_1_ushort` — the 64% of runtime the
Linux `perf` profile pointed at — are **at or better than parity on Windows**. The entire gap was
PETSc's BLAS-1 calls.

**Cause:** MSYS2's OpenBLAS is built multithreaded and forks/joins a thread team per call at a
fixed ~50 µs regardless of vector length. PETSc issues ~110k `BLASaxpy` calls per run on ~15.7k-element
vectors — just above the parallelisation threshold. Ubuntu's reference netlib BLAS is
single-threaded and never pays it, so **Linux was winning despite the objectively worse BLAS
library**.

The cleanest control needs no second machine: within one Windows run, `VecAYPX` (PETSc's own C
loop) costs **8.1 µs/call** while `VecAXPY` (routed to BLAS) costs **54.7 µs/call** on the same
vectors, same call count.

With one BLAS thread, VecAXPY reaches **7885 Mflop/s** — faster than Linux — and `KSPSolve` lands
at 18.91 s against Linux's 18.03 s.

### ⚠️ `OPENBLAS_NUM_THREADS` does nothing here

MSYS2's OpenBLAS uses the **OpenMP** backend (`libopenblas.dll` imports `libgomp-1.dll`), and an
OpenMP-backend OpenBLAS ignores both `OPENBLAS_NUM_THREADS` and `openblas_set_num_threads()`.
Measured one variable at a time on the 1-rank case:

| environment | wall clock | VecAXPY |
|---|---:|---:|
| neither | 38.15 s | 6.34 s / 552 Mflop/s |
| `OPENBLAS_NUM_THREADS=1` | 37.54 s | 6.14 s / 570 — **inert** |
| `OMP_NUM_THREADS=1` | **27.97 s** | 0.46 s / **7530** |

The variable everyone reaches for is the useless one. **Now fixed in the source**
(`src/globals/blasthreads.c`), so no environment variable is needed — rebuild to pick it up:

| build | before | after (no env vars) |
|---|---:|---:|
| `build-poisson-boris-petsc-mpi` | 37.81 s | **27.54 s** |
| `build-poisson-boris-petsc-mpi-o3petsc` | 38.15 s | **27.28 s** |

---

## GPU: measured, and it is a loss

ABBA-ordered with cooldowns, 2 reps per arm. `build-maxwell-dsmc-release-mpi` vs `…-gpu` differ in
exactly one CMake option, so this is a clean single-variable A/B. GPU is an **RTX 3060**.

| ranks | CPU [s] | GPU [s] | speedup | GPU util | VRAM |
|---:|---:|---:|---:|---:|---:|
| 1 | 412.51 | 442.94 | **0.93×** | 0 % | 870 MiB |
| 2 | 202.73 | 230.00 | **0.88×** | 1 % | 1156 MiB |
| 4 | 125.74 | 130.43 | **0.96×** | 6 % | 1706 MiB |
| 6 | 97.45 | 111.31 | **0.88×** | 6 % | 2264 MiB |

The GPU arm lost **all eight pairs**, including the reps where it ran first on the cooler machine.
Utilisation of 0–6% is the story: PICLas offloads only the **particle push**, while collision,
pairing, **tracking**, sampling and the field solve stay on the CPU, so each step pays a
host↔device copy to run one cheap kernel. At 1 rank the GPU is uncontended and still 0.93×, so
per-rank GPU sharing is not the explanation.

**PIC cannot be measured at all:** every GPU build is `LIBS_USE_PETSC=OFF` (so no
`PrecondType=2/4`), and `build-poisson-boris-mpi-gpu` also lacks superB — it aborts at
`init_BGField.f90:422 'Activate SuperB.'`. A build with all three options would still be expected
to give ~1.00×: that case has ~12 particles and ~94% of its runtime is the HDG field solve.

---

## Element-major HDG MatVec: 1.85×

A different axis — optimising PICLas' own internal CG rather than comparing platforms. One binary,
`HDGElemMajorMatVec` switch, 4 ranks, 7 solves, warm-up + ABBA.

| rep | side-major (F) | element-major (T) | paired ratio |
|---|---:|---:|---:|
| 1 | 0.031747 | 0.017084 | 1.86× |
| 2 | 0.030544 | 0.015988 | 1.91× |
| 3 | 0.030824 | 0.016667 | 1.85× |
| **median** | **0.030824 s/iter** | **0.016667 s/iter** | **1.85×** |

**Higher than the 1.5× measured when the change first landed**, because that predated Phase 1
(flat trace vectors, 2.03×) and the inlined Cholesky (1.13×). Those removed most of the
*non-MatVec* cost, so the MatVec is now a larger fraction of a much smaller total. Absolute
s/iteration went 0.0370 → **0.0167**. **Amdahl cuts both ways — an optimisation's value rises as
everything around it gets faster.**

---

## Caveats that change how to read the above

1. **The box throttles ~20% under sustained all-core load**, 12% of it within the first ~20 s, and
   recovers fully after 5 idle minutes. The DSMC 4-/6-rank rows ran last in an hour-long sweep and
   are **plateau (hot) values**; their parallel efficiency is understated and is **not** a property
   of PICLas. Measure in the plateau — discard 2–3 warm-up runs — because a cold run is 20% faster
   but you get one per five idle minutes.
2. **Always use ABBA ordering for two-arm comparisons.** A fixed A-then-B order manufactures a
   5–20% difference out of nothing. This contaminated the first CPU-vs-GPU reading.
3. **Cross-session absolute comparisons are unreliable**; drift is 3–6%. Same-session *ratios* are
   sound. Two published claims died to this: "Windows edges ahead on multi-rank DSMC" (does not
   reproduce — a tie) and PETSc `-O3` "1.6%" (noise; really 3.6%).
4. **Linux was never re-run with matching methodology** — single runs, no warm-up discipline, and
   still on reference netlib BLAS (~12% of its profile). Its column would move if fixed, so the
   residual 0.80–0.97 band is **not a settled figure**.
5. **The per-kernel `-log_view` comparison is stronger evidence than any wall-clock table here**,
   because it is immune to all of the above.
6. **The PIC case is chaotic — never diff its state file.** The two preconditioners the benchmark
   itself sweeps end 1.2e-1 apart in L2 with different particle counts, and both are accepted.

---

## Bottom line

- **PIC at 1 rank went from 0.66× to 0.99× — parity.** The penalty was two build asymmetries of
  our own making, not Windows, MinGW, MS-MPI, the Win64 ABI, the memory subsystem or huge pages,
  all of which were tested and refuted.
- **Multi-rank PIC sits at 0.80–0.90×**, attributable to MatMult vectorising ~14% better under
  GCC 11.2 than GCC 15.2/MinGW. Worth ~1 s on a 27 s run; not worth chasing.
- **DSMC was at parity wherever it was measured cleanly** (1 and 2 ranks). It links no PETSc and
  never hit any of this.
- **The GPU builds are a 4–14% loss** on this class of work.
- **Recommended Windows configuration:** the `-o3petsc` PIC binary; the BLAS fix is now automatic.
