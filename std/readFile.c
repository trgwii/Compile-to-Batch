#ifndef READ_FILE_H
#define READ_FILE_H

#include "Result.h"
#include "Str.h"
#include "defs.h"
#include "readAllAlloc.c"
#include <stdio.h>

static Result(Str) readFile(const char *path) {
  FILE *f = fopen(path, "r");
  if (!f) {
    return Result_Err(Str, "could not open file");
  }
  Result(Str) res = readAllAlloc(f);
  if (fclose(f)) {
    return Result_Err(Str, "could not close file");
  }
  return res;
}

#endif /* READ_FILE_H */
