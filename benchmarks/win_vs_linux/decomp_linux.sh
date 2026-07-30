#!/bin/bash
# Linux mirror of the Windows epsCG decomposition. 1 rank, PrecondType=2.
# See NEXT_ON_LINUX.md step 2. Windows reference: T = 6.9 s + 2.13 s x iters.
set -e
source /home/alopp/benchmarks/win_vs_linux/bench_env.sh
HERE=/home/alopp/benchmarks/win_vs_linux
CASE=$HERE/pic_hempt_hdg
BIN=$PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas
WORK=/tmp/pic_decomp; rm -rf $WORK; mkdir -p $WORK

# parameter.ini ships PrecondType = 2,4 for reggie's sweep -- pin it to 2 for a direct run.
sed 's/^PrecondType\(.*\)=.*2,4/PrecondType\1= 2/' $CASE/parameter.ini > $WORK/base.ini
grep -E '^PrecondType' $WORK/base.ini

stage() {   # stage(dir)
  local d=$1
  mkdir -p $d/pre-hopr
  cp $CASE/DSMC.ini $CASE/HEMPT_90deg_BGField.h5 $d/
  cp $CASE/pre-hopr/90_deg_segment_mesh.h5 $d/pre-hopr/
}

for tag in tight:5e-5 mid:1e-3 loose:1e-1; do
  name=${tag%%:*}; eps=${tag##*:}
  d=$WORK/$name; stage $d
  sed "s/^epsCG\(.*\)=.*5e-5/epsCG\1= $eps/" $WORK/base.ini > $d/parameter.ini
  ( cd $d && mpirun -np 1 $BIN parameter.ini DSMC.ini > std.out 2>&1 )
  t=$(grep -a "PICLAS FINISHED" $d/std.out | sed 's/.*\[ *\([0-9.]*\) sec.*/\1/')
  it=$(grep -a -o "#iterations *: *[0-9]*" $d/std.out | awk '{s+=$NF;n++} END {printf "%.2f", s/n}')
  echo "LINUX $name eps=$eps time=$t avgiters=$it"
done

# and the solve/no-solve split
d=$WORK/skip; stage $d
sed 's/^PrecondType\(.*\)= 2/PrecondType\1= 2\nHDGSkip = 100\nHDGSkipInit = 100/' $WORK/base.ini > $d/parameter.ini
( cd $d && mpirun -np 1 $BIN parameter.ini DSMC.ini > std.out 2>&1 )
echo "LINUX skip $(grep -a 'PICLAS FINISHED' $d/std.out)"
