#!/bin/bash
# Phase 0 re-run: element-major vs side-major HDG CG MatVec (commit 7d75c55).
#
# One binary, both paths, selected by the `HDGElemMajorMatVec` ini switch, so nothing but the
# summation order differs. PETSc is OFF in this build, so the internal CG (the thing being
# optimised) is what actually runs.
#
# METRIC IS SECONDS PER CG ITERATION, NOT WALL CLOCK. Element-major reassociates the sum, so the
# iteration count may shift by up to ~1.6% on some cases; wall clock would confound the two.
# PICLas prints `RunTime/iteration [s]` per solve; we take the mean over the case's 7 solves.
#
# Protocol (new, from the 2026-07-30/08-03 thermal characterisation):
#   * WARMUP discarded runs first -- the box loses 20% from cold to plateau, 12% of it within the
#     first ~20 s of load, and only the plateau is reproducible (flat to 1.9%).
#   * ABBA ordering per repetition, so any residual drift cancels instead of being attributed to
#     whichever arm ran second.
# The original Phase 0 measurement noted an unexplained 9% spread between its two side-major reps
# and called it "a warm-up/cache artifact" -- that is this effect, now characterised.
set -u
ROOT=/c/Data/PRJ/piclas-win/piclas-win-master
BIN=$ROOT/build-perf-hdg/bin/piclas-win.exe
BENCH=/c/Data/PRJ/Magnetron2D/bench
SC=/c/Users/andre/AppData/Local/Temp/claude/c--Data-PRJ/e899b174-03b0-415f-875a-e64f23ce02a3/scratchpad
WORK=$SC/hdg_ab
REPS=${1:-2}
WARMUP=${WARMUP:-2}
RANKS=${RANKS:-4}

export PATH="$ROOT/build-perf-hdg/bin:/c/msys64/ucrt64/bin:$PATH"
export HDF5_USE_FILE_LOCKING=FALSE

rm -rf "$WORK"; mkdir -p "$WORK"
for arm in F T; do
  d=$WORK/$arm; mkdir -p "$d"
  # bench_skip1.ini does not set the switch (default .TRUE.) -- append it explicitly per arm.
  sed "s/^ProjectName\( *\)=.*/ProjectName\1= bench$arm/" $BENCH/bench_skip1.ini > "$d/bench.ini"
  printf '\n! A/B: side-major (F) vs element-major (T) CG MatVec\nHDGElemMajorMatVec = %s\n' "$arm" >> "$d/bench.ini"
  grep -q "^HDGElemMajorMatVec = $arm$" "$d/bench.ini" || { echo "FATAL: switch not set for arm $arm"; exit 1; }
  cp $BENCH/DSMC.ini "$d/"
done

# mean seconds/iteration over the run's solves, plus the iteration counts (correctness gate)
metrics() { # $1=logfile
  awk '/RunTime\/iteration/ {gsub(/[Dd]/,"E",$NF); s+=$NF; n++}
       /#iterations/ {c=$3; gsub(/[^0-9]/,"",c); it=it c ","}
       END {printf "%.6f %d %s", (n?s/n:0), n, it}' "$1"
}

run() { # $1=arm $2=tag -> "s_per_iter nsolves iters"
  local d=$WORK/$1
  ( cd "$d" && mpiexec -n $RANKS "$BIN" bench.ini DSMC.ini > "$d/$2.log" 2>&1 )
  metrics "$d/$2.log"
}

echo "# warm-up: $WARMUP discarded runs (element-major arm, the faster one)"
for w in $(seq 1 $WARMUP); do run T warmup$w > /dev/null; done

echo "rep,arm,s_per_iter,nsolves,iterations"
for r in $(seq 1 $REPS); do
  if [ $((r % 2)) -eq 1 ]; then order="F T"; else order="T F"; fi
  for arm in $order; do
    read -r spi n its <<< "$(run $arm rep$r)"
    echo "$r,$arm,$spi,$n,${its%,}"
  done
done
