/*
 * userblock_stub.c - Windows fallback for the userblock object file.
 * Provides the symbols that the PICLas linker expects.
 * On Linux, userblock.o is created by objcopy from the compressed userblock
 * archive. On Windows we supply empty/stub symbols instead.
 */
#include <stddef.h>

static const char piclas_userblock_data[] = "PICLAS_USERBLOCK_WINDOWS_STUB";

const char*  userblock_start = piclas_userblock_data;
const char*  userblock_end   = piclas_userblock_data + sizeof(piclas_userblock_data);
const size_t userblock_size  = sizeof(piclas_userblock_data);
