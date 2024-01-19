#ifndef WRITE_ALL_H
#define WRITE_ALL_H

#include "Result.h"
#include "defs.h"
#include <stdio.h>

#ifdef BUILDING_WITH_ZIG
extern void writeAll(FILE *f, Slice(char) str);
#else
static void writeAll(FILE *f, Slice(char) str) {
  size_t written = 0;
  size_t total_written = 0;
  while ((written =
              fwrite(str.ptr + total_written, 1, str.len - total_written, f))) {
    total_written += written;
  }
}
#endif

#endif /* WRITE_ALL_H */
