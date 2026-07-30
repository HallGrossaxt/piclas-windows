#!/bin/bash
# Step 3 of NEXT_ON_LINUX.md -- huge-pages test on the tight (eps=5e-5) case, 1 rank, PrecondType=2.
#
# Two things had to be sorted out before this test was valid:
#
# 1. /sys/kernel/mm/transparent_hugepage/enabled is [madvise] on this box, NOT [always].
#    glibc's malloc never calls madvise(MADV_HUGEPAGE) on its own, so the *default* Linux run
#    already has PETSc's heap on 4 KB pages -- the same page size Windows uses. Switching THP
#    to "never" therefore measures nothing; the informative direction is to turn huge pages ON.
#    glibc 2.35+ can do that per process with no root: GLIBC_TUNABLES=glibc.malloc.hugetlb=1.
#
# 2. If the launching process has THP disabled via prctl(PR_SET_THP_DISABLE) -- which is
#    inherited across fork/exec -- both the tunable and any madvise() are silently ignored.
#    Check with: awk '/^THP_enabled:/' /proc/<pid>/status  (0 = disabled).
#    ./thpon clears the flag before exec'ing, so the "on" arm really gets 2 MB pages.
#
# Runs are interleaved (base, thp, base, thp, ...) so session drift cannot masquerade as effect.
set -e
source /home/alopp/benchmarks/win_vs_linux/bench_env.sh
HERE=/home/alopp/benchmarks/win_vs_linux
BIN=$PICLAS_ROOT/build-poisson-boris-petsc-mpi/bin/piclas
THPON=$HERE/thpon
cd /tmp/pic_decomp/tight

echo "THP sysfs   : $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
echo "THP_enabled : $(awk '/^THP_enabled:/{print $2}' /proc/self/status) (this shell)"

time_run() {   # time_run(env-prefix...) -> seconds on stdout
  mpirun -np 1 -x GLIBC_TUNABLES "$@" $BIN parameter.ini DSMC.ini 2>&1 \
    | grep -a "PICLAS FINISHED" | sed 's/.*\[ *\([0-9.]*\) sec.*/\1/'
}

faults() { awk '/^thp_fault_alloc /{print $2}' /proc/vmstat; }

for i in 1 2 3; do
  # arm A: default -- 4 KB pages
  export GLIBC_TUNABLES=
  f0=$(faults); b=$(time_run); fb=$(( $(faults) - f0 ))
  # arm B: 2 MB pages -- prctl cleared + glibc told to madvise
  export GLIBC_TUNABLES=glibc.malloc.hugetlb=1
  f0=$(faults); h=$(time_run $THPON); fh=$(( $(faults) - f0 ))
  echo "pair $i:  base_4k=${b}s (thp_faults=$fb)   hugepages=${h}s (thp_faults=$fh)"
done
