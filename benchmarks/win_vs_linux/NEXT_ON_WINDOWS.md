# Continue here on the Windows boot — ✅ COMPLETED 2026-07-30, GAP RESOLVED

> **All four steps in this runbook were executed on the Windows boot on 2026-07-30.**
> Results are in [`LINUX_RESULTS.md`](LINUX_RESULTS.md) → "Windows-side session, 2026-07-30".
> **The investigation is closed. There is no open question and no further handoff.**
>
> **Cause: MSYS2's OpenBLAS is built multithreaded.** PETSc calls `BLASaxpy` ~110k times on
> ~15.7k-element vectors, just above OpenBLAS's threshold for going parallel, so it forks and
> joins a thread team 110,000 times — a fixed ~50 µs per call against ~4 µs on Linux, whose
> reference netlib BLAS is single-threaded. **`OPENBLAS_NUM_THREADS=1` takes the 1-rank case
> from 36.70 s to 27.26 s against Linux's 27.47 s: parity.**
>
> Outcomes against this runbook's expectations:
> - **§2 Step 1 — the DLL hypothesis was structurally impossible.** The Windows PETSc is a
>   static `libpetsc.a`, so nothing is resolved at runtime; verified by `CMakeCache.txt`,
>   `CC_FLAGS`, and `objdump` of the two archives. Re-measured interleaved over 7 pairs:
>   `-O3` is worth **3.6%** (a third of that being 15.50→15.30 iterations, not speed).
>   **The original 1.6% was noise, not a botched experiment**, and Linux's 11.4% does not
>   transfer because 16% of the Windows runtime sat in OpenBLAS, out of PETSc's reach.
> - **§3 Step 2 — done, and it answered everything.** `MatMult` and `MatSolve` are at or
>   **better** than parity on Windows (5338 vs 4901, 3793 vs 3722 Mflop/s). `VecAXPY` is
>   **13.6x slower** (6.03 s vs 0.44 s). Best control: within the same Windows run, `VecAYPX`
>   (PETSc's own C) costs 8.1 µs/call while `VecAXPY` (BLAS) costs 54.7 µs/call.
> - **§4 Step 3 — done, and it is a dead end.** The `-O1` MatMult inner loop really is 12
>   instructions with the base pointers spilled to stack, versus 8 with FMA at `-O3`. But
>   Windows `-O1` already beats Linux `-O1` on that kernel, so MinGW codegen was never the
>   problem. GCC 15.2 vs 11.2 is off the hook except for a residual 1.14x on MatMult at `-O3`.
> - **§5 Step 4 — the tables are corrected**, with the new `OPENBLAS_NUM_THREADS=1` row.
> - **Scope:** the penalty is **1-rank only**. By 2 ranks it is within noise and by 4 ranks
>   `-log_view` shows VecAXPY already at 24335 Mflop/s with default OpenBLAS — decomposition
>   drops each rank's vectors below OpenBLAS's parallelisation threshold. This retro-explains
>   why the original table showed 0.66x at 1 rank but 0.81–0.87x at 2/4/6.
>
> **Recommended Windows PIC configuration:** `petsc-msmpi-O3` + `OPENBLAS_NUM_THREADS=1`.
> Do **not** expect it to move the magnetron numbers — that runs at MPI=4–6, past the threshold.

Original handoff, written 2026-07-30 from the **Linux** side, after executing every step of
[`NEXT_ON_LINUX.md`](NEXT_ON_LINUX.md), follows below. Its §2 framing (the DLL hypothesis) and its
§4 framing (that MinGW codegen of the two hot kernels is the remaining question) both turned out
to be wrong; they are kept for the record.

---

## 1. What changed

The gap is now **1.37x, not 1.53x**, and it is localised to two functions.

| finding | status |
|---|---|
| Linux PETSc flags | `-O3 -march=native -mtune=native` → the PIC rows were **`-O1` vs `-O3`** all along |
| `epsCG` decomposition | Linux `T = 5.91 s + 1.179 s·iters` vs Windows `6.94 s + 2.134 s·iters` |
| fixed per-solve HDG Fortran | **4.67 s (Win) vs 4.65 s (Linux) — exact parity** |
| iteration-proportional CG work | 33.07 s vs 18.28 s — **1.81x**, the entire gap |
| transparent huge pages | **refuted**, ~2% (third strike) |
| `perf` | IPC **3.50**, dTLB miss **0.02%** → issue-bound, **not** memory-bound |
| `perf` top symbols | **64%** in `MatSolve_SeqSBAIJ_1_NaturalOrdering` (37.9%) + `MatMult_SeqSBAIJ_1_ushort` (26.2%) |
| PETSc `-O1` vs `-O3` on Linux | **11.4%** (MatMult 1.30x, MatSolve 1.08x) |

**Refuted, do not re-test:** `-fstack-arrays` (3%), transparent huge pages (2%), memory
bandwidth / TLB, PICLas' own Fortran, BLAS (Windows has the *better* BLAS — Linux only has
reference netlib BLAS, correcting an earlier claim), MPI vendor, iteration counts.

### Linux reference numbers, 1 rank, PrecondType=2

| quantity | Linux |
|---|---|
| full run, `epsCG=5e-5` (15.50 avg iters) | **24.65 s** (median of 3) |
| same, but PETSc built `-g -O` like Windows | **27.47 s** (median of 3) |
| `epsCG=1e-3` (8.90 iters) | 16.68 s |
| `epsCG=1e-1` (2.00 iters) | 8.27 s |
| fit: fixed cost `C` | 5.91 s |
| fit: per-iteration slope `k` | 1.179 s/iter |
| `HDGSkip=100` | 1.26 s |
| MatMult / MatSolve / KSPSolve | 6352 / 4014 / 4869 Mflop/s |

> Cross-session drift is **3–6%** (up to 15% at 6 ranks). Interleave repeats; never compare a
> single number across days. All Linux numbers above are medians of interleaved runs.

---

## 2. Step 1 — re-verify the `-O3` PETSc measurement (do this first, it is probably wrong)

The Windows session measured **1.6%** for the PETSc `-O3` rebuild at block-Jacobi. Linux measures
**11.4%** for the identical swap on identical source, with `MatMult` (27% of runtime) alone
speeding up 1.30x. 1.6% is not a plausible total.

**Prime suspect: the `-O3` DLL was never actually loaded.** On Windows, linking against
`petsc-msmpi-O3`'s import library does not determine which `libpetsc` DLL is *mapped* at
runtime — `PATH` search order does. The old `-O1` `petsc-msmpi` install is still present and
working (it was deliberately left untouched), which is exactly the setup where this goes wrong.

Check which DLL the process actually mapped:

```powershell
# while the run is in flight
Get-Process piclas | Select-Object -ExpandProperty Modules |
  Where-Object { $_.ModuleName -like "*petsc*" } |
  Select-Object ModuleName, FileName, FileVersionInfo
```

or `listdlls.exe piclas` (Sysinternals), or simply `tasklist /m libpetsc*`.

If it shows the `petsc-msmpi` path rather than `petsc-msmpi-O3`, the 13.8% GAMG / 1.6%
block-Jacobi numbers in `LINUX_RESULTS.md` are both invalid and the whole `-O3` question is
**reopened**. Re-run with the O3 `bin` directory *prepended* to `PATH`, and confirm the mapped
path before trusting the timing.

The Linux equivalent of this test needed no rebuild at all, because the soname is identical —
`petsc_opt_swap.sh` just reorders `LD_LIBRARY_PATH` and prints the resolved path per arm. Do the
same verification-before-timing on Windows.

## 3. Step 2 — get `-log_view` from Windows (2 minutes, highest value)

This is the best instrument for what remains, and it did not exist when the Windows session ran.
`Count` and `Flop` are algorithmic and must match Linux exactly; the **Mflop/s column is then a
drift-free, single-run, per-kernel speed comparison** — no interleaving, no session-drift caveat.

```powershell
$env:PETSC_OPTIONS="-log_view"
.\piclas.exe parameter.ini DSMC.ini > logview_win.txt 2>&1
```

Compare against `results/logview_linux_bjacobi_1rank.txt` (PETSc `-O3`) and
`results/logview_linux_bjacobi_1rank_petscO1.txt` (PETSc `-g -O`, matching the Windows flags).
Save as `results/logview_win_bjacobi_1rank.txt` and add a `!` line to
`benchmarks/win_vs_linux/.gitignore`.

Expected, if the story holds: identical `Count`/`Flop`, and `MatMult`/`MatSolve` Mflop/s roughly
1.37x below the Linux `-O1` column.

## 4. Step 3 — disassemble the two hot functions

This is the whole remaining question, and it no longer needs whole-program experiments. Same
source, same flags (once Step 1 is settled), same generic arch — 1.37x apart:

- `MatSolve_SeqSBAIJ_1_NaturalOrdering` (37.9% of runtime)
- `MatMult_SeqSBAIJ_1_ushort` (26.2%)

```bash
# in an MSYS2 shell, against the same libpetsc that the run actually maps
objdump -d --disassemble='MatMult_SeqSBAIJ_1_ushort' /path/to/libpetsc.dll > win_matmult.s
objdump -d --disassemble='MatSolve_SeqSBAIJ_1_NaturalOrdering' /path/to/libpetsc.dll > win_matsolve.s
```

and on Linux:

```bash
objdump -d --disassemble='MatMult_SeqSBAIJ_1_ushort' /home/alopp/petsc/3.24.5-O1/lib/libpetsc.so.3.24 > lin_matmult.s
```

Use the `3.24.5-O1` build for the comparison — it is the flag-matched one. What to look for:
instruction count in the inner loop, whether the loop is vectorised on one side only, spills,
and whether MinGW's ABI forces extra register save/restore. GCC 11.2 vs 15.2 is a live variable
again now that the hot code is this localised — earlier it was dismissed on the weak grounds that
the newer compiler "should" be faster.

## 5. Step 4 — fix the fair-comparison baseline in the tables

Once Step 1 is resolved, the headline PIC table in `LINUX_RESULTS.md` should quote **both sides at
the same PETSc optimisation level**. Two of the three ratios are already computed:

| comparison | Windows | Linux | ratio |
|---|---:|---:|---:|
| as originally reported | 37.67 s (`-O1`) | 24.65 s (`-O3`) | 1.53x |
| **fair, both `-g -O` generic** | **37.67 s** | **27.47 s** | **1.37x** |
| fair, both `-O3 -march=native` | 37.05 s **(suspect)** | 24.65 s | 1.50x |

## 6. Also worth doing on Windows

- **Rebuild the production PETSc with `-O3 -march=native`.** Worth ~11% on Linux; unlike
  `-fstack-arrays` and the earlier 1.6% claim this is a real production win at 1 rank. Note the
  earlier caveat still stands: measured on Windows the GAMG `-O3` gain **decayed to nothing by
  4 ranks**, so do not expect it to move the magnetron numbers at MPI=4+ — but re-measure that
  decay after Step 1, since it was measured with the possibly-unloaded DLL.
- **Install OpenBLAS on the Linux side** (separate, small): the Linux PETSc reports
  `-llapack -lblas` resolving to Ubuntu's reference netlib BLAS, and BLAS is ~12% of the Linux
  profile (`dgemv`/`dsymv`/`ddot`/`daxpy`, from PICLas' HDG Fortran). Linux is currently winning
  *despite* the slower BLAS. Only affects the Linux column, not the diagnosis.

## 7. Traps recorded this session

- **`prctl(PR_SET_THP_DISABLE)` is inherited across `fork`/`exec`** and silently makes
  `madvise(MADV_HUGEPAGE)` and `GLIBC_TUNABLES=glibc.malloc.hugetlb=1` no-ops. Any THP experiment
  must check `awk '/^THP_enabled:/' /proc/<pid>/status` (`0` = disabled) and verify
  `thp_fault_alloc` in `/proc/vmstat` actually advances. `thpon.c` clears the flag.
  The process launching a benchmark may have set it without you knowing.
- **THP on this box is `[madvise]`, not `[always]`** — so the default run is *already* on 4 KB
  pages and the runbook's "set THP to `never`" test would have measured nothing.
- **PETSc `configure` requires `PETSC_DIR` to be the source tree**, but `bench_env.sh` exports it
  as the *install prefix*; `build_petsc_o1.sh` overrides it. Failing to do so aborts configure
  while still exiting 0.
- **`--with-debugging=0` alone gives `-g -O`.** Both PETSc builds on both OSes confirmed this;
  always pass `COPTFLAGS`/`FOPTFLAGS` explicitly.

## 8. Scripts added on the Linux side

| file | purpose |
|---|---|
| `decomp_linux.sh` | `epsCG` sweep + `HDGSkip` split → the `C`/`k` fit |
| `thp_linux.sh` | interleaved 4 KB vs 2 MB page test, verifies THP faults per run |
| `thpon.c` | clears an inherited `PR_SET_THP_DISABLE`, then `exec`s |
| `build_petsc_o1.sh` | PETSc 3.24.5 with the Windows flags (`-g -O`) → `/home/alopp/petsc/3.24.5-O1` |
| `petsc_opt_swap.sh` | interleaved `-O3` vs `-O1` PETSc via soname swap, verifies the mapped library |

Nothing is committed — the Linux boot has no clone of the repo (`/home/alopp/piclas` is an
unpacked 4.2.0 source tree, not a git checkout). These files live in
`/home/alopp/benchmarks/win_vs_linux/` and need copying into the repo on the Windows side, where
the relevant commits are `68c4960`, `cc1094a`, `d23b628`, `19b32af`, `736bd1f`.
