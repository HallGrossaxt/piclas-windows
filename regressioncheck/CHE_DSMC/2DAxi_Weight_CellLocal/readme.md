# 2D-axisymmetric cell-local particle weighting

Two-stage regression for `Part-Weight-Type = cell_local`:

1. `parameter-pre.ini` runs the case with `Part-Weight-Type = radial`, producing a
   `DSMCState` that contains `WeightingFactorCell`.
2. `parameter.ini` restarts that state with `Part-Weight-Type = cell_local` and
   `Particles-MacroscopicRestart = T`, so the weight adaption in
   `PERFORM CELL-LOCAL WEIGHTING` is executed.

Checked:

* The adaption runs to completion. It previously segfaulted for every reference
  simulation without BGK/FP quality factors, because `nVar_FP` in
  `ReadinForCellLocalWeighting` was left uninitialised and then used as an index
  into the `ElemData` array.
* `ElemLocalWeight` in the resulting state file is compared against a reference.
  The adapted distribution is a function of the seeding `DSMCState` alone, so it
  has to be identical for `MPI = 1, 2, 4`. The per-element weights were formerly
  gathered to displacement zero on every rank in the sequential-HDF5 write path,
  which left most of the container uninitialised for `MPI > 1`.
