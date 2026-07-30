#!/bin/bash
# Does PETSc's optimisation level explain the Windows/Linux PIC gap?
#
# perf says 64% of the run is MatSolve_SeqSBAIJ + MatMult_SeqSBAIJ inside libpetsc, at IPC 3.5
# (issue-bound, not memory-bound) -- the regime where -O1 vs -O3 -march=native should matter a
# lot. Yet the Windows -O3 PETSc rebuild moved block-Jacobi by only 1.6%. Those cannot both hold.
#
# This measures the same swap on Linux, where it is clean: build_petsc_o1.sh produced a PETSc with
# the *Windows* flags (-g -O, generic arch) and an identical soname (libpetsc.so.3.24), so the
# unchanged piclas binary loads either one depending on LD_LIBRARY_PATH order. One variable.
#
# Runs are interleaved and the loaded library is verified per run, because "I relinked but the old
# library was still loaded" is precisely the failure mode under suspicion on the Windows side.
set -e
source /home/alopp/benchmarks/win_vs_linux/bench_env.sh
BIN=$PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas
O3=/home/alopp/petsc/3.24.5/lib
O1=/home/alopp/petsc/3.24.5-O1/lib
cd /tmp/pic_decomp/tight

for d in $O3 $O1; do
  printf '%-34s %s\n' "$(basename $(dirname $d))" \
    "$(grep -o '\-O[0-9g ]*-\?m\?a\?r\?c\?h\?=\?[a-z]*' $d/petsc/conf/petscvariables | head -1)"
  grep '^CC_FLAGS' $d/petsc/conf/petscvariables | grep -o '\-O.*$'
done

# prove the swap actually changes which file is mapped
for d in $O3 $O1; do
  echo "LD_LIBRARY_PATH=$d -> $(LD_LIBRARY_PATH=$d:$LD_LIBRARY_PATH ldd $BIN | awk '/libpetsc/{print $3}')"
done

run() {  # run(libdir) -> seconds
  LD_LIBRARY_PATH=$1:$LD_LIBRARY_PATH mpirun -np 1 -x LD_LIBRARY_PATH \
    taskset -c 0 $BIN parameter.ini DSMC.ini 2>&1 \
    | grep -a "PICLAS FINISHED" | sed 's/.*\[ *\([0-9.]*\) sec.*/\1/'
}

echo "--- interleaved, 3 pairs ---"
for i in 1 2 3; do
  a=$(run $O3); b=$(run $O1)
  echo "pair $i:  petsc-O3=${a}s   petsc-O1(windows flags)=${b}s"
done

# and the per-kernel Mflop/s under -O1, to compare with the -O3 log_view already on file
PETSC_OPTIONS=-log_view LD_LIBRARY_PATH=$O1:$LD_LIBRARY_PATH taskset -c 0 \
  $BIN parameter.ini DSMC.ini > /tmp/pic_decomp/logview_O1.txt 2>&1
echo "--- -O1 log_view (compare Mflop/s to the -O3 run) ---"
grep -E '^(MatMult|MatSolve|KSPSolve|PCApply) ' /tmp/pic_decomp/logview_O1.txt
