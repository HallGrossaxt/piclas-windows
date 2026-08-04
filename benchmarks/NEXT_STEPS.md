# Resume here — state as of 2026-08-04

Handoff for the performance / benchmark / release work. Read
[`SPEED_SUMMARY.md`](SPEED_SUMMARY.md) first for *what was measured*; this file is *where things
stand and what to do next*.

---

## 1. Repository state — read this before touching anything

| | |
|---|---|
| branch | `master`, **1 commit ahead of `origin/master`** |
| unpushed | `0206b62` — banner fix (commit hash + port version) |
| uncommitted | `.github/scripts/build_petsc_msmpi.sh`, `.github/workflows/release.yml` |
| latest tag | **`v2.3`**, released 2026-08-04, all six CI jobs green |

**The two uncommitted files are real work, deliberately held back**, and a `git checkout .` would
destroy them. They are backed up as a patch outside the repo:

```
C:\Data\PRJ\piclas-win\pending_release_tweaks.patch      # git apply to restore
```

They contain, both **written but never validated** (`bash -n` and a YAML parse are still owed):

1. **`build_petsc_msmpi.sh`** — adds `COPTFLAGS`/`FOPTFLAGS`/`CXXOPTFLAGS` =
   `-O3 -march=x86-64-v2 -mtune=generic` (portable; overridable via `PETSC_OPTFLAGS`), plus a
   post-install guard that fails the build if `CC_FLAGS` lacks `-O3` or contains `-march=native`.
   **Why it matters:** the shipped PETSc is currently `-g -O` (i.e. `-O1`) because
   `--with-debugging=0` alone silently downgrades. Worth ~3% at 1 rank, ~0 at MPI≥4.
   **Note:** the workflow's PETSc cache key hashes this script, so editing it forces a genuine
   rebuild rather than restoring the `-O1` cache. No extra action needed.
2. **`release.yml`** — GPU note upgraded from "no meaningful speedup" to the measured
   0.93/0.88/0.96/0.88× at 0–6% utilisation; a `PrecondType` line (block-Jacobi at 1 rank, GAMG
   from 2 up); and a runtime note that BLAS is pinned to one thread and that
   `OPENBLAS_NUM_THREADS` is inert on this build.

---

## 2. What shipped in v2.3

- **The BLAS threading fix** (`1451699`) — the only runtime change. Verified end-to-end by
  downloading the published `piclas-win-picmc-v2.3-win64.zip` and running it: it prints
  `BLAS pinned to 1 thread per rank (override with OMP_NUM_THREADS)`.
- Everything else in the tag is benchmarks and documentation.

**Known limitations shipped in v2.3**, both recorded in the tag message:
- PETSc inside the bundle is `-O1` (item 1 above).
- The release notes still carry the old GPU wording (item 2 above).
- The binary's banner shows an **empty commit hash** and **"piclas-win 2.0"** — fixed by the
  unpushed `0206b62`, so it will correct itself in the next release.

---

## 3. Open work, roughly by value

### a) Linux re-run with matching methodology — the one real gap

Every `linux/win` ratio in `SPEED_SUMMARY.md` compares **single Linux runs** (2026-07-28) against
**Windows repeat-medians**. Mismatched methodology, so the residual 0.80–0.97× band is *not* a
settled figure. On the Linux boot:

1. `apt install libopenblas-*` and select it via `update-alternatives` — Linux is still on
   Ubuntu's reference netlib BLAS (~12% of its profile), so its column is currently understated.
   **Make sure it is the single-threaded build, or export `OMP_NUM_THREADS=1`** — otherwise Linux
   walks into exactly the pathology this whole investigation was about.
2. Re-run the sweep with repeats + warm-up + ABBA, mirroring `sweep_repeats_win.sh`.
3. Rebuild with the current source so Linux also gets the BLAS pinning (it is a Windows-only
   no-op today — see `src/globals/blasthreads.c` — so on Linux the env var is still the lever).

Only then is the OS table apples-to-apples. Everything needed is in
`win_vs_linux/NEXT_ON_LINUX.md` (its earlier steps are all complete) and `bench_env.sh`.
Note the Linux boot has **no git clone**; scripts written there must be copied back by hand.

### b) Push `0206b62`

It only takes effect in CI, so it does nothing until pushed. No tag needed — it will ride along
with whatever release is cut next.

### c) Decide on the two held-back edits

Validate, commit, and cut a `v2.4` — or drop them. Both are cheap; the PETSc one is the only
change with a measurable (if small) runtime effect.

### d) Open question, not decided: raise the ISA floor

Presets target `-march=x86-64-v2` (no AVX2, no FMA). The disassembly work showed FMA is exactly
what `-O3` exploits in `MatMult`, so `x86-64-v3` would likely beat the PETSc flag change — but it
drops pre-Haswell (pre-2013) CPUs. **That is a support-policy call, not a technical one.**
If taken, `PICLAS_INSTRUCTION` in `CMakePresets.json` and `PETSC_OPTFLAGS` in
`build_petsc_msmpi.sh` must move together.

---

## 4. Rules that were paid for — do not relearn these

- **Measure in the thermal plateau.** This box loses ~20% from cold to plateau, 12% of it within
  the first ~20 s of load, recovering fully after 5 idle minutes. Discard 2–3 warm-up runs, then
  take the median of ≥3. `sweep_repeats_win.sh` does this via `WARMUP=2`.
  Curve: `win_vs_linux/results/thermal_probe_win.csv`.
- **ABBA-order any two-arm comparison.** A fixed A-then-B order manufactures a 5–20% difference
  out of nothing. This contaminated the first CPU-vs-GPU reading.
- **`OPENBLAS_NUM_THREADS` is inert here** — MSYS2's OpenBLAS uses the OpenMP backend. The knob is
  `OMP_NUM_THREADS`. Checking `objdump -p libopenblas.dll | grep 'DLL Name'` for `libgomp-1.dll`
  is how this was settled; **don't truncate that list**, the original `head -12` hid the answer.
- **`PETSC_OPTIONS=-log_view` is the best instrument in this project.** `Count`/`Flop` are
  algorithmic and match across machines, so the Mflop/s column is a drift-free per-kernel
  comparison immune to all of the above. It found the bug after a day of wall-clock work had
  chased the wrong two kernels.
- **`git check-ignore -v` before adding any data file.** The repo root ignores `*.csv`, `*.h5`,
  `*.log`; files vanish silently otherwise. Both benchmark directories carry local `.gitignore`
  negations for exactly this.
- **Benchmark seconds per CG iteration, never wall clock**, for anything touching the HDG MatVec —
  reassociation moves the iteration count.
- **`ninja -t clean` an old build dir before trusting it.** `build-perf-hdg` link-failed on a
  stale `mpi_shared.f90.obj` predating an import rename; incremental builds do not catch it.

---

## 5. Where things live

| | |
|---|---|
| consolidated results | `benchmarks/SPEED_SUMMARY.md` |
| OS benchmark + investigation | `benchmarks/win_vs_linux/` (`RESULTS.md`, `LINUX_RESULTS.md`) |
| HDG MatVec A/B | `benchmarks/hdg_matvec/` |
| HDG phase plan | `C:\Data\PRJ\piclas-win\plan_hdg_acceleration.md` (outside the repo) |
| held-back release edits | `C:\Data\PRJ\piclas-win\pending_release_tweaks.patch` |
| the BLAS fix itself | `src/globals/blasthreads.c` + `src/piclaslib.f90` |
