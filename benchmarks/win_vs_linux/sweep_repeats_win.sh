#!/bin/bash
# Windows sweep with repeats, in the FIXED configuration.
#
# Why this exists alongside run_benchmark.ps1: that driver runs reggie once per point, and
# single runs on this box are worth +-3-6% (up to 15% at 6 ranks). Two headline claims died to
# that. This script runs every point N times and reports all reps plus the median, and it bakes
# in the two fixes found on 2026-07-30:
#
#   * OPENBLAS_NUM_THREADS=1 -- MSYS2's OpenBLAS is multithreaded and PETSc calls BLASaxpy ~110k
#     times per PIC run on vectors just above its parallelisation threshold. Worth 1.35x at
#     1 rank; a no-op from 2 ranks up. See blas_threads_win.sh.
#   * the -o3petsc PIC binary -- PETSc built -O3 -march=native instead of the -g -O default
#     that `--with-debugging=0` silently produces. Worth ~3%.
#
# Output: results/win_timings_fixed.csv        (medians, same schema as win_timings.csv)
#         results/win_timings_fixed_raw.csv    (every repetition)
#
# Usage:  ./sweep_repeats_win.sh [reps] [work_dir]
# Runtime: ~65 min at reps=3 (DSMC 1-rank alone is ~400 s). Keep the box otherwise idle.
set -u
ROOT=${PICLAS_ROOT:-/c/Data/PRJ/piclas-win/piclas-win-master}
HERE=$ROOT/benchmarks/win_vs_linux
REPS=${1:-3}
WORK=${2:-/c/Data/PRJ/piclas-win/piclas-win-master/benchmarks/win_vs_linux/results/sweep_fixed}

PIC_BIN=$ROOT/build-poisson-boris-petsc-mpi-o3petsc/bin/piclas-win.exe
DSMC_BIN=$ROOT/build-maxwell-dsmc-release-mpi/bin/piclas-win.exe
# Overridable so the mechanics can be smoke-tested cheaply before committing an hour:
#   RANKS=6 CASES=pic ./sweep_repeats_win.sh 1 /tmp/smoke
RANKS=${RANKS:-"1 2 4 6"}
CASES=${CASES:-"pic dsmc"}

# The fix. Applies to both cases: DSMC barely touches BLAS, but keeping the environment
# identical across cases removes a variable rather than adding one.
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1

for b in "$PIC_BIN" "$DSMC_BIN"; do
  [ -x "$b" ] || { echo "FATAL: binary not found: $b"; exit 1; }
done

RAW=$HERE/results/win_timings_fixed_raw.csv
MED=$HERE/results/win_timings_fixed.csv
rm -rf "$WORK"; mkdir -p "$WORK" "$HERE/results"
echo "os,case,solver,ranks,rep,sec" > "$RAW"

# --- case setup: frozen .h5 inputs, copied never regenerated -------------------------------
setup_pic() { # $1=dest  $2=PrecondType
  mkdir -p "$1/pre-hopr"
  sed "s/^PrecondType\(.*\)= *2,4/PrecondType\1= $2/" $HERE/pic_hempt_hdg/parameter.ini > "$1/parameter.ini"
  grep -q "^PrecondType.*= *$2 *$" "$1/parameter.ini" || { echo "FATAL: PrecondType not pinned to $2"; exit 1; }
  cp $HERE/pic_hempt_hdg/DSMC.ini $HERE/pic_hempt_hdg/HEMPT_90deg_BGField.h5 "$1/"
  cp $HERE/pic_hempt_hdg/pre-hopr/90_deg_segment_mesh.h5 "$1/pre-hopr/"
}
setup_dsmc() {
  mkdir -p "$1/pre-hopr"
  cp $HERE/dsmc_periodic3d/parameter.ini $HERE/dsmc_periodic3d/DSMC.ini "$1/"
  cp $HERE/dsmc_periodic3d/pre-hopr/periodic_mesh.h5 "$1/pre-hopr/"
}

median() { sort -g | awk '{a[NR]=$1} END {if(NR%2) printf "%.2f",a[(NR+1)/2]; else printf "%.2f",(a[NR/2]+a[NR/2+1])/2}'; }

timed_run() { # $1=dir $2=bin $3=ranks $4=tag -> echoes seconds, or FAIL
  ( cd "$1" && mpiexec -n $3 "$2" parameter.ini DSMC.ini > "$1/$4.out" 2>&1 )
  local t
  t=$(grep -a "PICLAS FINISHED" "$1/$4.out" | sed 's/.*\[ *\([0-9.]*\) *sec.*/\1/')
  [ -n "$t" ] && echo "$t" || echo FAIL
}

sweep() { # $1=case  $2=solver-label  $3=bin  $4=setup-fn  $5=PrecondType(pic only)
  local case=$1 solver=$2 bin=$3 setupfn=$4 pt=${5:-}
  for n in $RANKS; do
    local d=$WORK/${case}_${solver}_r$n
    if [ "$case" = pic ]; then $setupfn "$d" "$pt"; else $setupfn "$d"; fi
    local vals=""
    for r in $(seq 1 $REPS); do
      local t; t=$(timed_run "$d" "$bin" "$n" "rep$r")
      echo "win,$case,$solver,$n,$r,$t" | tee -a "$RAW"
      [ "$t" != FAIL ] && vals="$vals$t"$'\n'
    done
    if [ -n "$vals" ]; then
      echo "win,$case,$solver,$n,$(printf '%s' "$vals" | median)" >> "$MED.tmp"
    else
      echo "win,$case,$solver,$n,FAIL" >> "$MED.tmp"
    fi
  done
}

echo "os,case,solver,ranks,sec" > "$MED.tmp"
if [[ " $CASES " == *" pic "* ]]; then
  echo "### PIC, block-Jacobi (PrecondType=2), PETSc -O3, 1 BLAS thread"
  sweep pic BJACOBI "$PIC_BIN" setup_pic 2
  echo "### PIC, GAMG (PrecondType=4)"
  sweep pic GAMG    "$PIC_BIN" setup_pic 4
fi
if [[ " $CASES " == *" dsmc "* ]]; then
  echo "### DSMC (no PETSc)"
  sweep dsmc -      "$DSMC_BIN" setup_dsmc
fi

mv "$MED.tmp" "$MED"
echo
echo "===== medians of $REPS -> $MED"
cat "$MED"
echo
echo "===== raw -> $RAW"
