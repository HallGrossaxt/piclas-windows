/* thpon -- clear an inherited PR_SET_THP_DISABLE, then exec the given command.
 *
 * Needed because the process that launches these benchmarks may have THP disabled via
 * prctl(PR_SET_THP_DISABLE), which is inherited across fork/exec and silently makes any
 * MADV_HUGEPAGE (and the glibc.malloc.hugetlb tunable) a no-op. Check with
 *   awk '/^THP_enabled:/' /proc/<pid>/status
 * Build: gcc -O2 -o thpon thpon.c
 * Use:   thpon <cmd> [args...]
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/prctl.h>

int main(int argc, char **argv)
{
  if (argc < 2) { fprintf(stderr, "usage: thpon <cmd> [args...]\n"); return 2; }
  if (prctl(PR_GET_THP_DISABLE, 0, 0, 0, 0) == 1)
    if (prctl(PR_SET_THP_DISABLE, 0, 0, 0, 0) != 0)
      fprintf(stderr, "thpon: could not clear PR_SET_THP_DISABLE\n");
  execvp(argv[1], argv + 1);
  fprintf(stderr, "thpon: exec %s: %s\n", argv[1], strerror(errno));
  return 127;
}
