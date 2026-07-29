#!/usr/bin/env bash
# =====================================================================================================================
#  PICLas Windows-vs-Linux benchmark driver  (Linux side)
#  Mirror of run_benchmark.ps1 -- keep the two in lockstep.
#
#  Drives reggie against PREBUILT release binaries (-e) so we time the exact
#  shipped binary, never a fresh compile. Rank sweep + GAMG sweep come from the
#  case .ini files (command_line.ini: MPI=1,2,4,6 ; parameter.ini: PrecondType=2,4).
#
#  IMPORTANT for a fair comparison: build the two Linux binaries with the SAME
#  cmake options as the Windows builds (see README, "Reproducing on Linux"),
#  and copy the frozen inputs (*.h5) from the Windows tree instead of
#  regenerating them, so both OSes solve a byte-identical problem.
#
#  Usage:   ./run_benchmark.sh
#  Output:  logs/pic.log, logs/dsmc.log  ->  results/linux_timings.csv
# =====================================================================================================================
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

# --- knobs (edit to match your tree) -------------------------------------------------------------------------------
PICLAS_ROOT="${PICLAS_ROOT:-$HOME/piclas}"
REGGIE="${REGGIE:-reggie}"                     # reggie on PATH (pip install of reggie2.0)
PYTHON="${PYTHON:-python3}"
MPIEXE="${MPIEXE:-mpirun}"                      # reggie uses '-np <ranks> --oversubscribe' for mpirun

# PIC (HDG-Poisson): PETSc build with GAMG (poisson + Boris-Leapfrog + LIBS_USE_PETSC=ON).
PIC_BIN="${PIC_BIN:-$PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas}"
# DSMC: maxwell + TIMEDISC=DSMC, PETSc OFF.
DSMC_BIN="${DSMC_BIN:-$PICLAS_ROOT/build-maxwell-dsmc-release-mpi/bin/piclas}"

mkdir -p "$here/logs" "$here/results"

run_case () {
    local label="$1" casedir="$2" exe="$3"
    echo "==== $label :: $exe ===="
    [ -x "$exe" ] || { echo "binary not found/executable: $exe" >&2; exit 1; }
    # reggie -e sets run-mode (no compile) and writes each run's full stdout to std.out in its run dir.
    # Give each case its own output tree so the two cases never clobber each other.
    rm -rf "$here/output_dir" "$here/results/run_$label"
    "$REGGIE" "$casedir" -e "$exe" -m "$MPIEXE" -s 2>&1 | tee "$here/logs/$label.log"
    echo "reggie exit: ${PIPESTATUS[0]} (analyze is disabled; non-zero only means a run crashed)"
    [ -d "$here/output_dir" ] && mv "$here/output_dir" "$here/results/run_$label"
}

run_case pic  "$here/pic_hempt_hdg"   "$PIC_BIN"
run_case dsmc "$here/dsmc_periodic3d" "$DSMC_BIN"

"$PYTHON" "$here/parse_timings.py" --os linux --out "$here/results/linux_timings.csv" \
    --case "pic=$here/results/run_pic" --case "dsmc=$here/results/run_dsmc"
echo
echo "Done. See results/linux_timings.csv"
