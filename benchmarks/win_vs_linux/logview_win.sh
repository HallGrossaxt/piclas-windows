#!/bin/bash
# Capture PETSc's -log_view table on Windows for the 1-rank block-Jacobi PIC case.
#
# This is the best instrument in this benchmark and it is nearly free. `Count` and `Flop` are
# algorithmic and match across OSes, so the **Mflop/s column is a drift-free, single-run,
# per-kernel speed comparison** — no interleaving, no session-drift caveat. It is what
# identified VecAXPY (i.e. multithreaded OpenBLAS) as the entire Windows-vs-Linux PIC gap,
# after wall-clock experiments had chased the wrong two kernels for a day.
#
#   ./logview_win.sh [o1|o3] [ranks]
#
# Compare the resulting VecAXPY / MatMult / MatSolve rows against:
#   results/logview_linux_bjacobi_1rank.txt          (Linux, PETSc -O3)
#   results/logview_linux_bjacobi_1rank_petscO1.txt  (Linux, PETSc -g -O — flag-matched to o1)
#   results/logview_win_bjacobi_1rank.txt            (Windows o1, default OpenBLAS)
#   results/logview_win_bjacobi_1rank_blas1thread.txt(Windows o1, OPENBLAS_NUM_THREADS=1)
#   results/logview_win_bjacobi_4rank.txt            (Windows o1, 4 ranks — no BLAS penalty)
#
# Set OPENBLAS_NUM_THREADS=1 in the environment to capture the fixed configuration.
set -e
ROOT=${PICLAS_ROOT:-/c/Data/PRJ/piclas-win/piclas-win-master}
CASE=$ROOT/benchmarks/win_vs_linux/pic_hempt_hdg
arm=${1:-o1}
ranks=${2:-1}
case $arm in
  o1) BIN=$ROOT/build-poisson-boris-petsc-mpi/bin/piclas-win.exe ;;
  o3) BIN=$ROOT/build-poisson-boris-petsc-mpi-o3petsc/bin/piclas-win.exe ;;
  *)  echo "usage: $0 [o1|o3] [ranks]"; exit 1 ;;
esac
WORK=${WORK:-/tmp/pic_logview_$arm}

rm -rf "$WORK"; mkdir -p "$WORK/pre-hopr"
sed 's/^PrecondType\(.*\)= *2,4/PrecondType\1= 2/' $CASE/parameter.ini > "$WORK/parameter.ini"
grep -q '^PrecondType.*= *2 *$' "$WORK/parameter.ini" || { echo "FATAL: PrecondType not pinned"; exit 1; }
cp $CASE/DSMC.ini $CASE/HEMPT_90deg_BGField.h5 "$WORK/"
cp $CASE/pre-hopr/90_deg_segment_mesh.h5 "$WORK/pre-hopr/"

out=$WORK/logview_win_${arm}_${ranks}rank.txt
( cd "$WORK" && PETSC_OPTIONS="-log_view" mpiexec -n $ranks "$BIN" parameter.ini DSMC.ini > "$out" 2>&1 ) || true
grep -aq MatMult "$out" || { echo "FAIL: no -log_view table in $out"; tail -5 "$out"; exit 1; }

echo "== $out"
grep -a "PICLAS FINISHED" "$out"
grep -aE '^(MatMult|MatSolve|KSPSolve|PCApply|VecAXPY|VecAYPX|VecNorm) ' "$out"
