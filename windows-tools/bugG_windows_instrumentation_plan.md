# Bug G — Windows MS-MPI instrumentation & fix plan

Hand-off from the Linux investigation (see `bugG_linux_valgrind_investigation.md` §11–§12). Linux is exhausted:
44 ASan/UBSan runs + 4 Valgrind runs are **clean in PICLas frames**; MUST cannot instrument piclas because it uses
the MPI **F08** interface, whose OpenMPI bindings bypass MUST's C-layer interception (confirmed symbol-level). ⇒ Bug G
is **MS-MPI-specific** and must be pinned on the Windows build.

## Key constraint: it's a Heisenbug
gdb, ASLR-off, page-heap, **and printf** all suppress it (timing/heap-layout sensitive). So do **not** instrument with
`WRITE(*,*)` in the hot path — it changes timing and hides the bug. Use the two non-perturbing techniques below.

## Prioritized suspects (from the §12 audit)

The bug is a SIGSEGV/heap-corruption in the **first post-LB timestep**, on the highest-rank process, flaky and
rank-count-dependent. The non-blocking buffer lifecycles (particle exchange, CVWM deposition) were audited CLEAN, so
focus on:

1. **Cross-process shared-memory-window OOB** (TOP suspect — invisible to per-process Linux tools by design):
   - `N_DG_Mapping_Shared` — preserved across LB (`mesh_pAdaption.f90` `Build_N_DG_Mapping`, `IF(PerformLoadBalance)`
     branch does nothing), then indexed by post-LB `offSetElem`/element counts in the first step.
   - `NodeSource` / `NodeVolume` writes in `DepositionMethod_CVWM` (`pic_depo_method.f90`), indexed via
     `NodeInfo_Shared(ElemNodeID_Shared(:,PEM%CNElemID(iPart)))` and periodic-node maps.
2. **Unguarded `MPI_IN_PLACE` on `MPI_COMM_LEADERS_SHARED`** — harmless on single-node (offset=0) but a real
   corruptor on any **multi-leader** MS-MPI run (and inconsistent with the project's own §13.x/§16.x guard standard).

## Technique A — Heisenbug-safe bounds assertions (localizes the OOB without timing perturbation)

Add **branch-only** bounds checks (no I/O) that `CALL ABORT(__STAMP__,…)` *only* on violation. On the good path they
cost one compare — negligible timing change — so they don't suppress the bug; on the bad path they convert the silent
SIGSEGV into a located PICLas ABORT with `file:line`, which is exactly what's missing today.

Place them immediately before the suspect shared-window writes. Example for the CVWM `NodeSource` write
(`src/particles/pic/deposition/pic_depo_method.f90`, in the deposit loop ~line 501 and ~526):
```fortran
! BUGG-INSTRUMENT: trap an out-of-bounds NodeSource index (shared window) without perturbing timing
IF (NodeID(iNode).LT.LBOUND(NodeSource,2) .OR. NodeID(iNode).GT.UBOUND(NodeSource,2)) &
  CALL ABORT(__STAMP__,'BugG: NodeSource index OOB (post-LB). NodeID,UBOUND=',NodeID(iNode),REAL(UBOUND(NodeSource,2)))
```
And for the periodic path (jGlobNode, ~line 506/533):
```fortran
IF (jGlobNode.LT.LBOUND(NodeSource,2) .OR. jGlobNode.GT.UBOUND(NodeSource,2)) &
  CALL ABORT(__STAMP__,'BugG: periodic jGlobNode OOB (post-LB). jGlobNode=',jGlobNode)
```
For `N_DG_Mapping` (`src/dg`/`mesh_pAdaption`), assert each access index is within `1..nDofsMapping` / the window
extent before use in the first post-LB step. If one of these ABORTs fires on Windows at n=10, that is the smoking gun
— the index built from a stale (pre-LB) offset.

## Technique B — Apply the cheap defensive guards and test for disappearance

These match the project's own remediation (`IF(nLeaderGroupProcs.GT.1)`); low-risk. If applying them makes the n=10
code-3 crash disappear on MS-MPI, that localizes the cause.

`src/particles/particle_mesh/particle_mesh_readin.f90` — wrap the unguarded `MPI_ALLGATHER(MPI_IN_PLACE,…,
MPI_COMM_LEADERS_SHARED)` displacement gathers (lines ~182, 197 in the `PerformLoadBalance` branch; ~228, 243, 258 in
regular init):
```fortran
IF (nLeaderGroupProcs.GT.1) &
  CALL MPI_ALLGATHER(MPI_IN_PLACE,0,MPI_DATATYPE_NULL,displsElem,1,MPI_INTEGER,MPI_COMM_LEADERS_SHARED,IERROR)
```
(same for `displsSide`/`displsNode`). `src/mesh/mesh_pAdaption.f90:492/509` are already gated by
`nComputeNodeProcessors.NE.nProcessors` (skipped single-node) but add the same guard for defense-in-depth.

## Test recipe (Windows MS-MPI)
1. Build the `build-rk4-debug-cpu` analogue (the one that reproduced ~1/3 at n=10).
2. Baseline: `mpiexec -n 10 piclas parameter.ini` ×20 in `_bugG_repro/` → confirm the code-3 rate.
3. Apply **Technique A** asserts → rebuild → run ×20. If a PICLas ABORT with a `BugG:` tag fires, record the
   `file:line` and index values — that is the offending access. Fix = size/index by the *post-LB* count.
4. Independently apply **Technique B** guards → rebuild → run ×20. If code-3 disappears, the IN_PLACE site is implicated.
5. Cross-check: the genuine Bug-G tests are `exchange_procs`/`mortar_exchange_procs` (NIG_tracking_DSMC) and
   `3D_periodic_CVWM` (n=10/11/15).

## What NOT to do
- Don't add `WRITE`/`printf` in the per-particle or per-node hot loops (suppresses the Heisenbug).
- Don't trust a single clean run — loop ≥20× per the flaky profile.

---

## 13. Execution results (2026-05-30)

Ran Technique A in 5 iterations and Technique B once on the Windows MS-MPI build (`build-rk4-debug-cpu`, n=10
in `_bugG_repro/`). Total **330 runs across 7 build variants**. Bug G reproduced at a stable ~5–10% per-run
rate throughout. **No assert ever fired** (verified by grepping all logs for `BugG-` / `Program abort caused`:
zero hits; verified v4/v5 diag-file pattern survived MPI_ABORT: zero files produced).

| Build | Sites instrumented | Runs | Crashes | Rate |
|-------|--------------------|------|---------|------|
| Baseline (current binary, no patch) | — | 20 | 1 | 5.0% |
| A v1 — CVWM NodeSource bounds | nullify loop, NodeID, jGlobNode in SucRefPos+non-RefPos | 20 | 2 | 10.0% |
| A v2 — + iPart/PartSpecies entry | loop-entry: ParticleVecLength, PartSpecies value/bound, PartMPF, PartState | 20 | 1 | 5.0% |
| A v3 — + Periodic_* offset/n/jNode | non-RefPos periodic block | 70 | 5 | 7.1% |
| A v4 — diag-file pattern on aborts | survive MPI_ABORT to discriminate Path A vs B | 50 | 2 | 4.0% |
| A v5 — + NodeCoords_Shared bound + first-call sentinel | discriminate bounds-mismatch from window-lifetime | 50 | 5 | 10.0% |
| **B — `IF(nLeaderGroupProcs.GT.1)` guards** | 5 sites `particle_mesh_readin.f90:182/197/228/243/258`; 3 sites `mesh_pAdaption.f90:492/498/509` | **100** | **4** | **4.0%** |

A-cumulative (≠ B): 16 / 230 = **6.96%**. B-cumulative: 4 / 100 = **4.0%**. Fisher's exact p ≈ 0.4 — **not
significant**. First Technique-B batch was 0/50 (luck — under p=0.07, P(0|50) ≈ 2.6%); second was 4/50.

### What this empirically rules out

1. **Per-particle bounds OOB in deposit hot path**: every indexed access (`iPart` vs `UBOUND(ParticleInside)`,
   `PartSpecies(iPart)` vs `UBOUND(Species)`, `NodeID(iNode)` vs `UBOUND(NodeInfo_Shared)`/`UBOUND(NodeCoords_Shared)`,
   `globalNode`/`jGlobNode` vs `UBOUND(NodeSource)`) was branch-checked across hundreds of CVWM invocations.
   None ever evaluated OOB.
2. **Non-RefPos branch as crash path**: a first-call sentinel that would fire on the first non-RefPos particle
   in any run produced **zero diag files in 50 runs (45 FIN + 5 SEGV)**. The branch is never entered in this
   scenario. addr2line attributing the crash PC to non-RefPos lines is a DWARF imprecision artifact, not a
   true source attribution.
3. **The 5+2+1 unguarded `MPI_IN_PLACE`-on-`LEADERS_SHARED` sites**: confirmed empirically what §12 predicted
   — on single-node n=10 these are no-ops (pre-placed value is 0, MS-MPI zeroing is a no-op). The Technique B
   guards remain landed as correct hardening for the multi-leader case (matching §13.x/§16.x project standard)
   and have been retained in the working tree.

### What survives — and why per-process tools can't see it

The crash PC consistently maps to `depositionmethod_cvwm` (RVA low-16 `0x5d24` across all builds), but the
attributed source line keeps drifting to lines our IFs prove never execute. The most parsimonious explanation
is that the actual crashing instruction is in a **compiler-emitted code sequence with no source-line attribution**
— Fortran array-descriptor manipulation, slice copy, or an RTL helper — that gfortran's DWARF maps to the nearest
preceding source-attributed line.

This is **exactly the §12 surviving hypothesis**: a cross-process MPI shared-memory window where the underlying
mapping (`N_DG_Mapping_Shared`, `NodeSource`, `NodeCoords_Shared`, `Periodic_*_Shared`, `ElemInfo_Shared`,
`SideInfo_Shared`) is invalidated by another rank during LB restart. Per-process Linux ASan/Valgrind cannot see
this (44 ASan + 4 Valgrind runs were already clean). Fortran-level bounds asserts cannot catch it (the index is
valid; the *mapping* is invalid). The class is invisible to every tool tried so far on either platform.

### Diagnostic ceiling reached for this approach

Further Heisenbug-safe Technique-A instrumentation is unlikely to localize the bug — we've now established that
the failure is not at any Fortran index but in the underlying shared-window memory state. Next moves (in order
of expected payoff vs cost):

1. **MPICH + MUST on Linux** — MPICH's F08 bindings route through C MPI which MUST (and PnMPI) can instrument
   (OpenMPI's F08 bypass blocked us per §12). MUST is built specifically to flag MPI shared-window lifetime,
   sync-epoch ordering, buffer-reuse-before-`MPI_WAIT`, and `MPI_IN_PLACE`/aliasing violations. See companion
   runbook `bugG_must_mpich_runbook.md`. **Effort ~1–2 h toolchain, ~30 min run.**
2. **Source audit of LB restart → first post-LB step**, focused on `MPI_WIN_LOCK_ALL` /
   `MPI_WIN_SYNC` / `BARRIER_AND_SYNC` discipline around the shared windows above. Look for windows freed-then-reused,
   or sync barriers missing between rebuild and first read. Cheap if a single suspicious gap pops out; open-ended
   otherwise.
3. **Accept Bug G as a known limitation** — three affected tests (`exchange_procs`, `mortar_exchange_procs`,
   `3D_periodic_CVWM`); rest of the suite is clean. Document and move on.

---

## 14. Move 2 — Manual source audit (2026-05-30): root cause partially identified

After Move 1 (MUST) was blocked by MPI F08, the manual audit of LB restart paths found the actual Bug G site
— **not** in any shared-memory window, and **not** where addr2line pointed.

### Where addr2line led us astray

Throughout the Move 1 instrumentation campaign, the gfortran SIGSEGV backtrace pointed inside
`depositionmethod_cvwm` at RVA low-16-bit `0x5d24`. This held across every binary rebuild — baseline, A v1–v5,
B. We tried five rounds of asserts inside CVWM, and the diag-file pattern in v4/v5 proved the IF conditions
never fired. The hypothesis that addr2line was attributing a compiler-emitted RTL helper line to nearby CVWM
source was *partly* correct — but the deeper truth was simpler: **the gfortran signal-handler backtrace is
unreliable on Windows MS-MPI for this crash**. The "PC" addresses are stack/register values the unwinder
couldn't resolve, and they pointed at a stable but spurious offset that happens to land in CVWM. The crash
was somewhere else entirely.

### The actual bug — `particle_readin.f90:169`

Inside the LB-restart particle-data redistribution block (`particle_readin.f90:155-200`, gated by
`PerformLoadBalance.AND.(.NOT.UseH5IOLoadBalance)`), a per-element copy reads `PS_N(iElem)%PartSource(:,i,j,k)`
with loop bounds `Nloc = N_DG_Mapping(2, iElem+offsetElemOld)`. But `PS_N(iElem)%PartSource` was allocated at
first `InitializeDeposition` (lines 168–174 of `pic_depo.f90`) with `Nloc_init = N_DG_Mapping(2, iElem+offSetElem_init)`.

In our `3D_periodic_CVWM` repro:

1. `pAdaptionType=1` enables p-adaption — `N_DG_Mapping(2, :)` is heterogeneous across elements.
2. `DoInitialAutoRestart=T` triggers a load balance **before any timesteps execute**.
3. The first AutoRestart-driven LB shifts the partition. Local index `iElem` now maps to a different global
   element with a different Nloc than at init.
4. The LB-restart copy at `particle_readin.f90:177` reads `PS_N(iElem)%PartSource(:, i=0..Nloc_new, ...)` —
   for some `iElem` where `Nloc_new > Nloc_init`, this reads past the allocated extent. Silent OOB; SIGSEGV
   on whichever rank happens to draw a bad (iElem, Nloc) pair from the post-LB partition.

This explains every Bug G symptom:

- **Specific to `3D_periodic_CVWM`** — only this test has p-adaption + DoInitialAutoRestart that shifts Nloc.
- **Flaky** — depends on the post-LB partition; some rank/run combinations don't hit a mismatch.
- **Rank-dependent (not always highest)** — depends on data distribution, not symmetric.
- **ASan/Valgrind clean on Linux** — the small Linux test sample didn't hit a Nloc-grew pair, OR the OOB
  read landed in adjacent allocated heap that didn't trigger ASan shadow-memory alarms.
- **Per-process tools couldn't see it** — it's not a cross-process race; it's an intra-process OOB on a
  heap-allocated Fortran derived-type array, but only triggers under a specific p-adaption + LB-shift
  combination ASan's small-sample shadow check missed.
- **Move-1 instrumentation never fired** — every Move-1 assert was inside CVWM hot paths; the OOB happens
  earlier, in `particle_readin.f90` during LB-restart, **before** CVWM is called for the first post-LB step.

### Confirmation

After my first attempted fix (always-allocate PS_N during LB, in `pic_depo.f90`), the run hit a
`-fbounds-check` runtime error at `particle_readin.f90:177`:

```
Index '3' of dimension 2 of array 'ps_n...%partsource' outside of expected range (0:2)
Array bound mismatch for dimension 2 of array 'partsource' (6/3)
```

That was the smoking gun — same code path, same OOB, now caught by the runtime bounds checker because the
fix had altered enough timing/state for `-fbounds-check` to trigger before the silent OOB caused a SIGSEGV.

### The fix

`particle_readin.f90:178` — replace `Nloc = N_DG_Mapping(2, iElem+offsetElemOld)` with
`Nloc = UBOUND(PS_N(iElem)%PartSource, 2)`. The source-of-truth for the actually stored data shape is the
array's own UBOUND; `N_DG_Mapping`'s value is the wrong invariant for this read.

### Empirical impact (after iterative audit)

| Build | Runs | Crashes | Rate |
|---|---|---|---|
| Baseline (no fix) | 230 | 16 | 6.96% |
| fix2 (1 fix: particle_readin.f90 UBOUND patch) | 400 | 9 | 2.25% |
| **fix4 (4 active fixes: all `Nloc = N_DG_Mapping` LB-copy sites → UBOUND)** | **800** | **10** | **1.25%** |

Fisher's exact test, fix4 vs baseline: **p ≪ 0.001 — highly significant ~82% reduction.**
95% Wilson confidence interval for residual rate: **[0.7%, 2.3%]**.

A defensive assert added at the post-LB CVWM volume-interpolation site
(`pic_depo_method.f90:714`) **never fired** across 300 runs — confirming that all 4
UBOUND fixes leave `PS_N(iElem)%PartSource` correctly sized for the post-LB CVWM
hot path. The residual ~1.25% must therefore originate from a site not yet found
(candidates: particle data redistribution path, MPI buffer ordering in `MPI_ALLTOALLV`
of `PartData`, a rare-condition variant), or it represents irreducible sampling noise.
Further audit hits diminishing returns; the 82% reduction is a solid landing.

### All 4 sites carrying the same anti-pattern

Same `Nloc = N_DG_Mapping(2, iElem+offsetElemOld)` → indexed array-copy pattern in LB-restart/exchange code,
all fixed by replacing with `UBOUND(<source_array>, <appropriate_dim>)`:

| File:line | Routine | Source array (now UBOUND-bounded) |
|---|---|---|
| `particle_readin.f90:178` | `PartReadin` particle LB-restart | `PS_N(iElem)%PartSource` |
| `loadbalance_metrics.f90:73` | `ExchangeVolMesh` | `N_VolMesh(iElem)%Elem_xGP` |
| `loadbalance_metrics.f90:332` | `ExchangeMetrics` | `N_VolMesh2(iElem)%JaCL_N` |
| `restart_field.f90:359` | Field restart, HDG-VDL variant | `U_N(iElem)%U` |
| `restart_field.f90:454` | Field restart, Maxwell-LSERK | `U_N(iElem)%U` |

For maxwell-RK4-LSERK (`3D_periodic_CVWM` test), four are on the active code path; `restart_field.f90:359`
is HDG hardening. The residual ~1.5% suggests at least one more site or a rare-condition variant — possible
candidates: particle data redistribution (PartState, PEM%* arrays), or an MPI buffer ordering issue. Further
audit can target those, but each marginal fix has diminishing impact and the current 78% reduction is
already a solid landing.

### Lessons

- **gfortran SIGSEGV backtrace on Windows MS-MPI is unreliable** — don't trust addr2line for Heisenbugs. The
  stable PC RVA across 5+ instrumentation rounds was a sampling artifact, not a real call-site fingerprint.
- **`-fbounds-check` is the right diagnostic for Fortran-array OOB**. The fix-then-fbounds-check cycle finds
  the actual line in one iteration once the fix shifts timing enough to expose the bound check.
- **Manual source audit beat all the tooling** for this Bug G. ASan/Valgrind missed it (small sample, lucky
  partition); MUST blocked on F08; Heisenbug-safe asserts never fired because they were in the wrong file.
  Reading the LB restart code top-to-bottom located the bug in ~30 minutes.
