#!/bin/bash
# Windows counterpart of petsc_opt_swap.sh: interleaved A/B of PETSc `-g -O` vs
# `-O3 -march=native` on the 1-rank block-Jacobi PIC case.
#
# Unlike Linux, there is no library to swap at runtime — the Windows PETSc is a **static**
# libpetsc.a linked into libpiclas.dll, so the arm is selected by choosing the binary. That
# also means the "wrong DLL got loaded" failure mode suspected in NEXT_ON_WINDOWS.md §2
# cannot occur here. Confirm the two builds differ with:
#   grep '^CC_FLAGS' /c/Data/PRJ/petsc-msmpi{,-O3}/lib/petsc/conf/petscvariables
#
# Result (7 pairs, 2026-07-30): median 37.81 s -> 36.49 s = 3.6%, of which ~1 point is the
# `-O3` build averaging 15.30 CG iterations instead of 15.50 (FMA changes the rounding, hence
# the convergence path) rather than running faster. With OMP_NUM_THREADS=1 set on both
# arms it is 28.21 s -> 27.34 s = 3.2%.
#
# Beware: the paired spread is wide (0.14 s to 2.94 s). A single pair is worthless here —
# that is how the earlier "1.6%" arose. Run at least 3 pairs and take the median.
set -e
ROOT=${PICLAS_ROOT:-/c/Data/PRJ/piclas-win/piclas-win-master}
CASE=$ROOT/benchmarks/win_vs_linux/pic_hempt_hdg
WORK=${1:-/tmp/pic_petsc_ab}
REPS=${2:-3}

declare -A BIN
BIN[o1]=$ROOT/build-poisson-boris-petsc-mpi/bin/piclas-win.exe          # PETSc -g -O
BIN[o3]=$ROOT/build-poisson-boris-petsc-mpi-o3petsc/bin/piclas-win.exe  # PETSc -O3 -march=native

rm -rf "$WORK"
for arm in o1 o3; do
  d=$WORK/$arm; mkdir -p "$d/pre-hopr"
  # parameter.ini ships `PrecondType = 2,4` for reggie's sweep; pin it to 2 for a direct run.
  sed 's/^PrecondType\(.*\)= *2,4/PrecondType\1= 2/' $CASE/parameter.ini > "$d/parameter.ini"
  grep -q '^PrecondType.*= *2 *$' "$d/parameter.ini" || { echo "FATAL: PrecondType not pinned"; exit 1; }
  cp $CASE/DSMC.ini $CASE/HEMPT_90deg_BGField.h5 "$d/"
  cp $CASE/pre-hopr/90_deg_segment_mesh.h5 "$d/pre-hopr/"
done

echo "rep,arm,sec,avgiters"
for r in $(seq 1 $REPS); do
  for arm in o1 o3; do
    d=$WORK/$arm
    ( cd "$d" && mpiexec -n 1 "${BIN[$arm]}" parameter.ini DSMC.ini > "$d/std_$r.out" 2>&1 ) || true
    t=$(grep -a "PICLAS FINISHED" "$d/std_$r.out" | sed 's/.*\[ *\([0-9.]*\) *sec.*/\1/')
    it=$(grep -a -oE "#iterations *: *[0-9]+" "$d/std_$r.out" | awk '{s+=$NF;n++} END {if(n)printf "%.2f",s/n; else printf "NA"}')
    echo "$r,$arm,${t:-FAIL},$it"
  done
done
