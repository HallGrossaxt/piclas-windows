#if defined(_WIN32)
/* Windows (MSVC and MinGW/UCRT): sys/resource.h not available.
 * Stack size is controlled by the linker (/STACK flag or module definition). */
void setstacksizeunlimited(void)
{
  /* No-op on Windows: set stack size at link time or via application manifest */
}
#else
/* Linux/macOS/Unix: POSIX resource limits */
#include <sys/resource.h>

void setstacksizeunlimited(void)
{
   struct rlimit limit;
   getrlimit(RLIMIT_STACK, &limit);

   limit.rlim_cur=limit.rlim_max;

   setrlimit(RLIMIT_STACK, &limit);
}
#endif
