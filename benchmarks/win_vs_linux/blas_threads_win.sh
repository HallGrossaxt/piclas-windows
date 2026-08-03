#!/bin/bash
# The test that resolved the Windows-vs-Linux PIC gap (2026-07-30, Windows boot).
#
# Background: PETSc's -log_view showed that MatMult and MatSolve — the two kernels the
# Linux `perf` profile had blamed — are at or better than parity on Windows, while
# VecAXPY cost 6.03 s at 575 Mflop/s against 0.44 s at 7646 Mflop/s on Linux. Per call
# that is 54.7 us vs 4.1 us, a *fixed* overhead independent of vector length, which is
# the signature of a thread-team wakeup rather than of slow arithmetic. The Windows PETSc
# links MSYS2's OpenBLAS, which is built multithreaded and spawns a team of
# min(nproc, ...) threads per call; PETSc calls BLASaxpy ~110k times on vectors of a few
# thousand doubles, where the synchronisation dwarfs the work. Ubuntu's reference netlib
# BLAS on the Linux side is single-threaded, so it never pays this.
#
# Result: OMP_NUM_THREADS=1 takes the 1-rank block-Jacobi case from 36.70 s to
# 27.26 s (median of 3 interleaved pairs) against Linux's 27.47 s — i.e. parity. The whole
# 1.37x "residual gap" was this.
#
# Run from an MSYS2 shell. 1 rank, PrecondType=2, the frozen .h5 inputs.
set -e
ROOT=${PICLAS_ROOT:-/c/Data/PRJ/piclas-win/piclas-win-master}
BIN=$ROOT/build-poisson-boris-petsc-mpi/bin/piclas-win.exe
CASE=$ROOT/benchmarks/win_vs_linux/pic_hempt_hdg
WORK=${1:-/tmp/pic_blas}
REPS=${2:-3}

rm -rf "$WORK"; mkdir -p "$WORK/pre-hopr"
# parameter.ini ships `PrecondType = 2,4` for reggie's sweep; pin it to 2 for a direct run.
sed 's/^PrecondType\(.*\)= *2,4/PrecondType\1= 2/' $CASE/parameter.ini > "$WORK/parameter.ini"
grep -q '^PrecondType.*= *2 *$' "$WORK/parameter.ini" || { echo "FATAL: PrecondType not pinned"; exit 1; }
cp $CASE/DSMC.ini $CASE/HEMPT_90deg_BGField.h5 "$WORK/"
cp $CASE/pre-hopr/90_deg_segment_mesh.h5 "$WORK/pre-hopr/"

# Per-kernel proof first: -log_view with the thread team suppressed. Compare the VecAXPY
# row against results/logview_win_bjacobi_1rank.txt (default OpenBLAS).
( cd "$WORK" && PETSC_OPTIONS="-log_view" OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
    mpiexec -n 1 "$BIN" parameter.ini DSMC.ini > "$WORK/logview_blas1.txt" 2>&1 ) || true
echo "VecAXPY with 1 BLAS thread:"; grep -aE '^(VecAXPY|VecNorm|MatMult|MatSolve|KSPSolve) ' "$WORK/logview_blas1.txt"

# Then interleaved wall clock, so session drift (3-6% on this box) cancels.
echo "rep,arm,sec,avgiters"
for r in $(seq 1 $REPS); do
  for arm in many one; do
    if [ $arm = one ]; then export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
    else unset OPENBLAS_NUM_THREADS OMP_NUM_THREADS; fi
    ( cd "$WORK" && mpiexec -n 1 "$BIN" parameter.ini DSMC.ini > "$WORK/${arm}_$r.out" 2>&1 ) || true
    t=$(grep -a "PICLAS FINISHED" "$WORK/${arm}_$r.out" | sed 's/.*\[ *\([0-9.]*\) *sec.*/\1/')
    it=$(grep -a -oE "#iterations *: *[0-9]+" "$WORK/${arm}_$r.out" | awk '{s+=$NF;n++} END {if(n)printf "%.2f",s/n; else printf "NA"}')
    echo "$r,$arm,${t:-FAIL},$it"
  done
done
