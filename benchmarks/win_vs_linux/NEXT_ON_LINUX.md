# Continue here on the Linux boot — ✅ COMPLETED 2026-07-30

> **All five steps in this runbook were executed on the Linux boot on 2026-07-30.**
> Results are in [`LINUX_RESULTS.md`](LINUX_RESULTS.md) → "Linux-side session, 2026-07-30".
> **The work now continues on Windows: see [`NEXT_ON_WINDOWS.md`](NEXT_ON_WINDOWS.md).**
>
> Outcomes in brief:
> - **§3 Step 1** — Linux PETSc is `-O3 -march=native -mtune=native`. The PIC comparison was
>   `-O1` vs `-O3` all along. Recorded permanently in `LINUX_RESULTS.md`.
> - **§4 Step 2** — done. `T = 5.91 s + 1.179 s·iters` on Linux vs `6.94 + 2.134` on Windows;
>   iteration counts match. The **slope** differs 1.81x while the **fixed per-solve HDG Fortran
>   cost is at exact parity** (4.67 vs 4.65 s) — outcome row 1 of the table below.
> - **§5 Step 3** — **THP refuted (~2%)**. Note the test as written here would *not* have worked:
>   THP is `[madvise]` on this box, not `[always]`, so the baseline is already on 4 KB pages, and
>   an inherited `prctl(PR_SET_THP_DISABLE)` silently no-ops `madvise`/glibc tunables. See
>   `thp_linux.sh` and `thpon.c`.
> - **§6 Step 4** — done. IPC **3.50**, dTLB miss **0.02%** → **not memory-bound**, refuting this
>   file's framing. **64%** of runtime is `MatSolve_SeqSBAIJ_1_NaturalOrdering` +
>   `MatMult_SeqSBAIJ_1_ushort`.
> - **Extra** — PETSc `-O1` vs `-O3` measured on Linux by soname swap: **11.4%**, which
>   contradicts the Windows session's 1.6% and reopens that measurement.
>
> Residual gap after equalising PETSc flags: **1.37x**, down from 1.53x.

Handoff for the open question in this benchmark, written 2026-07-30 from the Windows side.
Everything below runs on the **Linux boot of the same dual-boot machine** (i5-13400F).

Read `LINUX_RESULTS.md` first for the full investigation; this file is just the runbook.

---

## 1. Where the work stands

**Settled.** The PIC case is ~94% HDG solve (`HDGSkip=100` cuts 39.7 s → 2.3 s; only ~12
particles, so deposition is negligible). Of that, **83% is iteration-proportional work inside
PETSc's CG** — an `epsCG` sweep on Windows fits `T = 6.9 s + 2.13 s x iters`, validated to 1.5%.
Per-solve **iteration counts are identical on both OSes** (both sum to 155 over the first ten
analyze points), so Windows is not doing more work — it runs the *same* sparse-CG work ~1.5x
slower on the *same* silicon.

**Refuted** (don't re-test): `-fstack-arrays` (3%), PETSc `-O3` (1.6% for block-Jacobi; the 13.8%
GAMG win it does give is 1-rank only and decays to nothing by 4 ranks), BLAS (OpenBLAS both
sides), compiler age (Windows has the *newer* GCC), MPI vendor (cannot affect a 1-rank number).

**Open.** Why are PETSc's memory-bound sparse kernels ~1.5x slower on Windows? Leading
hypothesis: **transparent huge pages** (Linux 2 MB by default, Windows 4 KB unless a process
holds `SeLockMemoryPrivilege`). A ~10–20 MB operator gathered irregularly in `MatMult` walks
thousands of 4 KB pages and pressures the L2 TLB, where 2 MB pages would need a handful.
**Two earlier hypotheses were refuted, so treat this one as unproven.**

### Windows reference numbers to compare against

1 rank, PrecondType=2 (block-Jacobi), `-march=native`, PETSc 3.24.5:

| quantity | Windows |
|---|---|
| full run, `epsCG=5e-5` (15.5 avg iters) | 40.01 s |
| `epsCG=1e-3` (8.5 iters) | 25.45 s |
| `epsCG=1e-1` (2.1 iters) | 11.42 s |
| fit: fixed cost `C` | **6.9 s** |
| fit: per-iteration slope `k` | **2.13 s / iter** |
| `HDGSkip=100` (solve+deposition removed) | 2.3 s |
| committed baseline (July, reggie) | 36.30 s |

> Cross-session drift on this machine is **3–6%, up to 15% at 6 ranks** (measured: same binaries,
> two days apart). Never compare a single Linux run against a Windows number from another day and
> call a <10% difference real. Interleave repeats.

---

## 2. Environment

```bash
source /home/alopp/piclas/benchmarks/win_vs_linux/bench_env.sh   # GCC 11.2 / OpenMPI 4.1.1 / HDF5 1.12.1 / PETSc 3.24.5 / reggie
cd $PICLAS_ROOT/benchmarks/win_vs_linux
```

Reminders:
- **Do not regenerate the `.h5` inputs.** The committed mesh + BGField are what make both OSes
  solve a byte-identical problem.
- The PIC build needs the **Ninja** generator — the Makefile generator's Fortran dep-scanner
  hangs on PETSc's `finclude` headers.
- Linux Release builds *do* get `-fstack-arrays` (Windows drops it); that asymmetry is already
  measured at 3% and is not what we're chasing.

---

## 3. Step 1 — fairness check on PETSc's own flags (2 minutes, do this first)

`PICLAS_INSTRUCTION` never reaches PETSc. The Windows PETSc turned out to be built `-g -O`
(**-O1, generic arch**) because `--with-debugging=0` without an explicit `COPTFLAGS` silently
falls back to plain `-O`. The Linux PETSc at `/home/alopp/petsc/3.24.5` was hand-built and its
flags were never recorded:

```bash
grep '^CC_FLAGS' $PETSC_DIR/lib/petsc/conf/petscvariables
```

- If it shows **`-O3`/`-march`** → the PIC comparison has been `-O1` vs `-O3` all along. Rebuild
  the *Windows* PETSc as the fair baseline (already done: `C:\Data\PRJ\petsc-msmpi-O3`, use the
  `build-poisson-boris-petsc-mpi-o3petsc` binary) and note it in `LINUX_RESULTS.md`.
- If it shows **`-g -O`** → both sides are `-O1`, the existing comparison was fair, and the
  optimisation level is ruled out entirely on both OSes.

Record the exact string in `LINUX_RESULTS.md` either way — it should never be unrecorded again.

---

## 4. Step 2 — repeat the `epsCG` decomposition on Linux (~2 minutes, highest value)

This is more informative than the THP test on its own, because it says **which term** of
`T = C + k·iters` differs. Save as `decomp_linux.sh` and run it:

```bash
#!/bin/bash
# Linux mirror of the Windows epsCG decomposition. 1 rank, PrecondType=2.
set -e
source /home/alopp/piclas/benchmarks/win_vs_linux/bench_env.sh
HERE=$PICLAS_ROOT/benchmarks/win_vs_linux
CASE=$HERE/pic_hempt_hdg
BIN=$PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas
WORK=/tmp/pic_decomp; rm -rf $WORK; mkdir -p $WORK

# parameter.ini ships PrecondType = 2,4 for reggie's sweep -- pin it to 2 for a direct run.
sed 's/^PrecondType.*=.*2,4/PrecondType = 2/' $CASE/parameter.ini > $WORK/base.ini

for tag in tight:5e-5 mid:1e-3 loose:1e-1; do
  name=${tag%%:*}; eps=${tag##*:}
  d=$WORK/$name; mkdir -p $d/pre-hopr
  sed "s/^epsCG.*=.*5e-5/epsCG = $eps/" $WORK/base.ini > $d/parameter.ini
  cp $CASE/DSMC.ini $CASE/HEMPT_90deg_BGField.h5 $d/
  cp $CASE/pre-hopr/90_deg_segment_mesh.h5 $d/pre-hopr/
  ( cd $d && mpirun -np 1 $BIN parameter.ini DSMC.ini > std.out 2>&1 )
  t=$(grep -a "PICLAS FINISHED" $d/std.out | sed 's/.*\[ *\([0-9.]*\) sec.*/\1/')
  it=$(grep -a -o "#iterations *: *[0-9]*" $d/std.out | awk '{s+=$NF;n++} END {printf "%.2f", s/n}')
  echo "LINUX $name eps=$eps time=$t avgiters=$it"
done

# and the solve/no-solve split
d=$WORK/skip; mkdir -p $d/pre-hopr
sed 's/^PrecondType = 2/PrecondType = 2\nHDGSkip = 100\nHDGSkipInit = 100/' $WORK/base.ini > $d/parameter.ini
cp $CASE/DSMC.ini $CASE/HEMPT_90deg_BGField.h5 $d/
cp $CASE/pre-hopr/90_deg_segment_mesh.h5 $d/pre-hopr/
( cd $d && mpirun -np 1 $BIN parameter.ini DSMC.ini > std.out 2>&1 )
echo "LINUX skip $(grep -a 'PICLAS FINISHED' $d/std.out)"
```

Then fit `T = C + k·iters` from the tight and loose points and compare to Windows
(`C = 6.9 s`, `k = 2.13 s/iter`):

| outcome | reading |
|---|---|
| `k` much lower on Linux, `C` similar | confirms the gap is **per-CG-iteration** work → memory/TLB story is live, go to Step 3 |
| `C` much lower, `k` similar | the gap is **fixed per-solve** cost (HDG assembly, PETSc setup) → the huge-pages hypothesis is wrong; look at the Fortran assembly path instead |
| both lower proportionally | a broad memory-subsystem effect, not specific to the CG kernels |

Also confirm `avgiters` matches Windows (15.5 / 8.5 / 2.1). If Linux converges in fewer
iterations at the same tolerance, part of the "gap" was never a speed difference at all.

---

## 5. Step 3 — the transparent-huge-pages test (the decisive one)

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled     # expect [always] or [madvise]

# baseline, 3 runs
for i in 1 2 3; do ( cd /tmp/pic_decomp/tight && mpirun -np 1 \
  $PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas parameter.ini DSMC.ini \
  | grep -a "PICLAS FINISHED" ); done

echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled

# THP off, 3 runs
for i in 1 2 3; do ( cd /tmp/pic_decomp/tight && mpirun -np 1 \
  $PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas parameter.ini DSMC.ini \
  | grep -a "PICLAS FINISHED" ); done

echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled   # RESTORE
```

Interpretation:

| Linux block-Jacobi with THP off | verdict |
|---|---|
| rises from ~24 s toward **~37 s** | **confirmed** — the gap is huge pages / TLB. Windows fix: large-page support needs `SeLockMemoryPrivilege` + PETSc large-page allocation; likely not worth it, but the benchmark can then state the cause honestly. |
| rises only a few % | **refuted** — third strike. Stop hypothesising and get a real profile (see Step 5). |

Don't forget to restore the THP setting.

---

## 6. Step 4 — if you want a real profile (Linux can do what Windows couldn't)

gprof is a dead end on MinGW (see `LINUX_RESULTS.md`), but Linux has `perf`, which needs no
rebuild and will name the exact kernels:

```bash
cd /tmp/pic_decomp/tight
perf record -g --call-graph dwarf -- $PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas parameter.ini DSMC.ini
perf report --stdio --sort symbol | head -40
# and the hardware counters that would settle the TLB question outright:
perf stat -e dTLB-load-misses,dTLB-store-misses,cache-misses,instructions,cycles \
  -- $PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas parameter.ini DSMC.ini
```

A high `dTLB-load-misses` rate that drops sharply with THP on vs off is direct evidence for the
huge-pages explanation. `perf report` should show `MatMult_SeqAIJ` / `MatSolve` / `VecDot`-family
symbols dominating if the 83%-in-CG finding holds on Linux too.

---

## 7. Step 5 — if you re-run the headline comparison, interleave it

The existing `linux_timings.csv` and `win_timings.csv` are single runs from *different sessions*,
which is why "Windows edges ahead on multi-rank DSMC" evaporated on re-run. If you want the
headline table to carry weight:

- 3+ repeats per point, and report median plus spread, not one number.
- Keep the box otherwise idle; the 6-rank points are the most drift-prone (15% observed).
- Same-session ratios (GAMG vs block-Jacobi) are trustworthy; cross-session absolute comparisons
  are not.

`run_benchmark.sh` still works for a plain sweep:

```bash
PICLAS_ROOT=$PICLAS_ROOT ./run_benchmark.sh      # -> results/linux_timings.csv
python3 parse_timings.py --compare results/win_timings.csv results/linux_timings.csv
```

> ⚠️ `run_benchmark.sh` deletes `results/run_pic` and `results/run_dsmc` before writing. On the
> Windows side the Linux raw output was rescued to `results/run_{pic,dsmc}_LINUX` — don't
> overwrite anything you still need.

---

## 8. What to write back

1. The PETSc `CC_FLAGS` string (Step 1) — into `LINUX_RESULTS.md`, permanently.
2. Linux `C` and `k` from the `epsCG` fit (Step 2), next to the Windows values.
3. The THP verdict (Step 3), replacing the "leading hypothesis" section in `LINUX_RESULTS.md`
   with a result — in either direction.
4. `perf` top symbols if you run Step 4.
5. Any new CSVs: add a `!results/<name>.csv` line to `benchmarks/win_vs_linux/.gitignore`, since
   the repo root ignores `*.csv`, `*.h5` and `*.log` — files vanish silently otherwise. Check
   with `git check-ignore -v <path>` before committing.

Relevant commits: `68c4960` (benchmark), `cc1094a`, `d23b628`, `19b32af`, `736bd1f`
(investigation). Nothing is pushed — this is all local on the Windows side.
