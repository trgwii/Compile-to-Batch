#ifndef READ_FILE_H
#define READ_FILE_H

#include "Allocator.c"
#include "Result.h"
#include "defs.h"
#include "readAllAlloc.c"
#include <stdio.h>

#ifdef BUILDING_WITH_ZIG
extern Result(Slice_char) readFile(Allocator ally, const char *path);
#else
static Result(Slice_char) readFile(Allocator ally, const char *path) {
  FILE *f = fopen(path, "r");
  if (!f) {
    return Result_Err(Slice_char, "could not open file");
  }
  Result(Slice_char) res = readAllAlloc(ally, f);
  if (fclose(f)) {
    if (res.ok)
      resizeAllocation(ally, char, &res.val, 0);
    return Result_Err(Slice_char, "could not close file");
  }
  return res;
}
#endif

#endif /* READ_FILE_H */
