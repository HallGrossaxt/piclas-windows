/*
 * glob_windows.c
 *
 * Win32 glob expansion helper for PICLas.
 * Called from Fortran (commandlinearguments.f90) via ISO_C_BINDING.
 *
 * glob_expand_c(pattern, results, results_len)
 *   Expands a single wildcard pattern using FindFirstFile / FindNextFile.
 *
 *   pattern     [in]  Null-terminated pattern string (may contain * or ?).
 *   results     [out] Buffer filled with matched filenames.  Each filename is
 *                     null-terminated; the list ends with an extra null byte
 *                     (double-null sentinel).  Results are returned in
 *                     alphabetically sorted order.
 *   results_len [in]  Size of the results buffer in bytes.
 *
 *   Returns the number of files found (0 = no match or no wildcard).
 *
 * On non-Windows platforms the function is compiled as a no-op stub so that
 * the same Fortran source can be used on Linux / macOS (where the shell
 * already expands globs before the program starts).
 */

#ifdef _WIN32

#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* Maximum files we will ever expand in one call */
#define GLOB_MAX_FILES 65536

/* Comparison function for qsort */
static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(const char **)a, *(const char **)b);
}

int glob_expand_c(const char *pattern, char *results, int results_len)
{
    WIN32_FIND_DATAA ffd;
    HANDLE           hFind;
    int              n_found = 0;
    int              offset  = 0;
    char             dir_prefix[MAX_PATH] = "";
    const char      *last_fwd, *last_back, *last_sep;
    char            *sorted[GLOB_MAX_FILES];
    int              i;

    /* ------------------------------------------------------------------
     * Extract the directory prefix (everything up to and including the
     * last path separator) so we can prepend it to each result filename.
     * ------------------------------------------------------------------ */
    last_fwd  = strrchr(pattern, '/');
    last_back = strrchr(pattern, '\\');
    if (last_fwd == NULL)  last_fwd  = pattern - 1;
    if (last_back == NULL) last_back = pattern - 1;
    last_sep = (last_fwd > last_back) ? last_fwd : last_back;

    if (last_sep >= pattern) {
        size_t prefix_len = (size_t)(last_sep - pattern) + 1;
        if (prefix_len < MAX_PATH) {
            strncpy(dir_prefix, pattern, prefix_len);
            dir_prefix[prefix_len] = '\0';
        }
    }

    /* Initialise result buffer */
    if (results_len > 0) results[0] = '\0';

    hFind = FindFirstFileA(pattern, &ffd);
    if (hFind == INVALID_HANDLE_VALUE) return 0;

    do {
        char  full_path[MAX_PATH];
        char *entry;
        int   full_len;

        /* Skip directories */
        if (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;

        if (dir_prefix[0] != '\0')
            snprintf(full_path, MAX_PATH, "%s%s", dir_prefix, ffd.cFileName);
        else
            strncpy(full_path, ffd.cFileName, MAX_PATH - 1);

        full_len = (int)strlen(full_path);
        entry = (char *)malloc(full_len + 1);
        if (!entry) break;
        memcpy(entry, full_path, full_len + 1);
        sorted[n_found++] = entry;

        if (n_found >= GLOB_MAX_FILES) break;

    } while (FindNextFileA(hFind, &ffd));

    FindClose(hFind);

    /* Sort results alphabetically (= chronological for zero-padded timestamps) */
    qsort(sorted, (size_t)n_found, sizeof(char *), cmp_str);

    /* Pack sorted results into the output buffer (null-separated, double-null end) */
    for (i = 0; i < n_found; i++) {
        int len = (int)strlen(sorted[i]);
        if (offset + len + 2 > results_len) {
            /* Buffer full - stop here */
            free(sorted[i]);
            n_found = i;
            break;
        }
        memcpy(results + offset, sorted[i], len);
        offset += len;
        results[offset++] = '\0';
        free(sorted[i]);
    }

    /* Double-null sentinel */
    if (offset < results_len) results[offset] = '\0';

    return n_found;
}

/*
 * piclas_total_physical_memory_c()
 *   Returns the total installed physical RAM in bytes, or 0 if it cannot be
 *   determined.  Used by particle_init.f90 to derive a safe default cap for
 *   Part-maxParticleNumber so that a runaway particle insertion aborts cleanly
 *   (via IncreaseMaxParticleNumber) instead of exhausting RAM and freezing the
 *   whole OS.
 */
long long piclas_total_physical_memory_c(void)
{
    MEMORYSTATUSEX statex;
    statex.dwLength = sizeof(statex);
    if (GlobalMemoryStatusEx(&statex))
        return (long long)statex.ullTotalPhys;
    return 0;
}

#else /* non-Windows stub */

int glob_expand_c(const char *pattern, char *results, int results_len)
{
    (void)pattern;
    (void)results;
    (void)results_len;
    return 0;
}

/* On Linux/macOS return 0 so the caller keeps the upstream HUGE() default. */
long long piclas_total_physical_memory_c(void)
{
    return 0;
}

#endif /* _WIN32 */
