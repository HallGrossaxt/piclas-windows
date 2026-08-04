# HDG CG MatVec: element-major vs side-major

A/B harness for the element-major matrix-vector product introduced in `7d75c55` (Phases 2+3 of
`piclas-win/plan_hdg_acceleration.md`). Per element the HDG CG MatVec is one dense
`nElemDOF x nElemDOF` product (24x24 at `N=1`), not 36 tiny 4x4 ones; `HDGElemMajorMatVec`
selects between the two paths **in the same binary**, so nothing but the summation order differs.

```bash
./hdg_matvec_ab.sh 3          # 3 ABBA repetitions after 2 warm-up runs (~12 min)
```

## Result, 2026-08-03 — 1.85x

Current `master` (all phases merged), `build-perf-hdg` (PETSc **OFF**, so the internal CG is what
actually runs), 4 ranks, `Magnetron2D/bench/bench_skip1.ini`, 7 solves. Raw:
`results_2026-08-03.csv`.

| rep | side-major (F) | element-major (T) | paired ratio |
|---|---:|---:|---:|
| 1 | 0.031747 | 0.017084 | 1.86x |
| 2 | 0.030544 | 0.015988 | 1.91x |
| 3 | 0.030824 | 0.016667 | 1.85x |
| **median** | **0.030824 s/iter** | **0.016667 s/iter** | **1.85x** |

Wall clock 128.18 s → 71.90 s = 1.78x (lower than the s/iter ratio because side-major runs 2 more
iterations and the non-solve cost is fixed).

**This is higher than the 1.5x measured when the change first landed**, and the reason is worth
remembering: that measurement predated Phase 1 (`b0297f5`, flat trace vectors, 2.03x) and the
inlined Cholesky (`067c18e`, 1.13x), which removed most of the *non-MatVec* cost. The MatVec is now
a larger fraction of a much smaller total, so reverting it costs proportionally more. Absolute
s/iteration went 0.0370 → **0.0167**. **Amdahl cuts both ways — an optimisation's value rises as
everything around it gets faster.**

## Rules

- **Metric is seconds per CG iteration, never wall clock.** Element-major reassociates the sum, so
  the iteration count can shift (up to 1.6% observed on `HDG_cylinder`); wall clock confounds
  speed with iteration count.
- **Correctness gate:** `L_2` unchanged **and** iterations within ~2%. The older "iteration counts
  must be bit-identical" invariant is retired for this change. Here element-major sums to **3941**
  over the 7 solves — exactly the recorded `Magnetron2D/bench/b_NEW.log` reference — and
  side-major to 3943 (+0.05%).
- **Warm up, then ABBA.** This box loses ~20% from cold to plateau, 12% of it within the first
  ~20 s of load. See `../win_vs_linux/RESULTS.md` and `results/thermal_probe_win.csv`. The original
  Phase 0 measurement recorded an unexplained 9% spread it called "a warm-up/cache artifact" —
  that was this. With 2 warm-up runs plus ABBA the three paired ratios agree to 3%.

## Build trap

`build-perf-hdg` can fail to link with:

```
undefined reference to `__mpi_f08_MOD_mpi_win_allocate_shared'
```

This is **not** a link-order or missing-shim problem. `src/mpi/mpi_shared.f90:28` renames on import
(`MPI_WIN_ALLOCATE_SHARED => PICLas_Win_allocate_shared`), and an old build directory can hold a
stale `mpi_shared.f90.obj` that still references the pre-rename symbol; the incremental build never
recompiles it. Run `ninja -t clean` in the build dir first, then rebuild.
