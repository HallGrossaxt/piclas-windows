#!/bin/bash
# CPU vs GPU on the DSMC case — interleaved, so session drift cancels.
#
# WHY ONLY DSMC: the two builds below differ in exactly one CMake option
# (PICLAS_USE_GPU) and agree on everything that matters — maxwell / DSMC /
# LIBS_USE_PETSC=OFF / Release / -march=x86-64-v2 -mtune=generic. That makes this a clean
# single-variable A/B.
#
# The PIC case CANNOT be measured this way. Every GPU build on this machine is
# LIBS_USE_PETSC=OFF, so it cannot run the benchmark's PrecondType=2/4 PETSc solvers at all
# (without PETSc, PrecondType selects the internal-CG preconditioner and GAMG is unavailable),
# and build-poisson-boris-mpi-gpu additionally lacks superB, so it aborts outright reading the
# frozen BGField:
#     init_BGField.f90:422  'Activate SuperB.'
# A meaningful PIC GPU number needs a new build with USE_GPU=ON + POSTI_BUILD_SUPERB=ON +
# LIBS_USE_PETSC=ON at -march=native. Expect ~1.0x from it regardless: this case carries only
# ~12 particles and ~94% of its runtime is the HDG field solve, which stays on the CPU.
#
# What PICLas' GPU support actually offloads is the particle PUSH (particle_push.cu / lserk
# push). Collision, pairing, tracking, sampling and the field solve remain on the CPU, so the
# Amdahl ceiling is set by the push fraction.
#
# NOTE: all ranks share the single RTX 3060; the binary warns that VRAM is partitioned per rank
# and suggests NVIDIA MPS for many-rank runs. That is part of what is being measured here.
set -u
ROOT=${PICLAS_ROOT:-/c/Data/PRJ/piclas-win/piclas-win-master}
HERE=$ROOT/benchmarks/win_vs_linux
REPS=${1:-2}
RANKS=${RANKS:-"1 2 4 6"}
WORK=${2:-$HERE/results/sweep_gpu}

CPU_BIN=$ROOT/build-maxwell-dsmc-release-mpi/bin/piclas-win.exe
GPU_BIN=$ROOT/build-maxwell-dsmc-release-mpi-gpu/bin/piclas-win.exe

# The GPU binary needs MSYS2's runtime DLLs (libgfortran/openblas/MS-MPI/HDF5) or it fails to
# load with no output at all.
export PATH="/c/msys64/ucrt64/bin:$PATH"
# Keep the BLAS environment identical to the CPU sweep (see blas_threads_win.sh). DSMC has no
# OpenMP and no BLAS hot path, so this changes nothing here — it just removes a variable.
export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1

for b in "$CPU_BIN" "$GPU_BIN"; do [ -x "$b" ] || { echo "FATAL: missing $b"; exit 1; }; done

RAW=$HERE/results/win_timings_gpu_raw.csv
rm -rf "$WORK"; mkdir -p "$WORK"
echo "os,case,arm,ranks,rep,sec" > "$RAW"

setup() { mkdir -p "$1/pre-hopr"
  cp $HERE/dsmc_periodic3d/parameter.ini $HERE/dsmc_periodic3d/DSMC.ini "$1/"
  cp $HERE/dsmc_periodic3d/pre-hopr/periodic_mesh.h5 "$1/pre-hopr/"; }

median() { sort -g | awk '{a[NR]=$1} END {if(NR%2) printf "%.2f",a[(NR+1)/2]; else printf "%.2f",(a[NR/2]+a[NR/2+1])/2}'; }

for n in $RANKS; do
  for arm in cpu gpu; do d=$WORK/${arm}_r$n; setup "$d"; done
done

# ABBA ordering is MANDATORY here, not a nicety. This box throttles hard under sustained
# all-core load: five consecutive identical 6-rank DSMC runs measured
# 88.24 / 91.78 / 92.31 / 105.16 / 109.05 s, a monotonic +24%. With a fixed cpu-then-gpu order
# the second arm is always the hot one and would look ~5-20% slower purely from heat.
# Alternating the order per repetition cancels that linear trend. COOLDOWN adds a little
# recovery between runs.
COOLDOWN=${COOLDOWN:-30}
for r in $(seq 1 $REPS); do
  for n in $RANKS; do
    if [ $((r % 2)) -eq 1 ]; then order="cpu gpu"; else order="gpu cpu"; fi
    for arm in $order; do
      d=$WORK/${arm}_r$n
      [ "$arm" = gpu ] && BIN=$GPU_BIN || BIN=$CPU_BIN
      sleep $COOLDOWN
      # Sample GPU utilisation mid-run once, to prove the device is actually doing work.
      if [ "$arm" = gpu ] && [ "$r" = 1 ]; then
        ( sleep 30; nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader \
            > "$d/gpu_util.txt" 2>&1 ) &
      fi
      ( cd "$d" && mpiexec -n $n "$BIN" parameter.ini DSMC.ini > "$d/rep$r.out" 2>&1 )
      t=$(grep -a "PICLAS FINISHED" "$d/rep$r.out" | sed 's/.*\[ *\([0-9.]*\) *sec.*/\1/')
      echo "win,dsmc,$arm,$n,$r,${t:-FAIL}" | tee -a "$RAW"
    done
  done
done

echo
echo "===== medians and GPU speedup (cpu/gpu; >1 means GPU is faster)"
printf "%-6s %10s %10s %8s\n" ranks cpu gpu speedup
for n in $RANKS; do
  c=$(awk -F, -v n=$n '$3=="cpu"&&$4==n&&$6!="FAIL"{print $6}' "$RAW" | median)
  g=$(awk -F, -v n=$n '$3=="gpu"&&$4==n&&$6!="FAIL"{print $6}' "$RAW" | median)
  s=$(awk -v c="$c" -v g="$g" 'BEGIN{if(g>0) printf "%.3f", c/g; else print "NA"}')
  printf "%-6s %10s %10s %8s\n" "$n" "$c" "$g" "$s"
done
echo
echo "GPU utilisation samples:"; for n in $RANKS; do
  [ -f "$WORK/gpu_r$n/gpu_util.txt" ] && echo "  $n ranks: $(cat "$WORK/gpu_r$n/gpu_util.txt")"; done
