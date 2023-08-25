#ifndef READ_ALL_ALLOC_H
#define READ_ALL_ALLOC_H

#include "Result.h"
#include "Str.h"
#include "defs.h"
#include "Allocator.c"
#include <stdio.h>

static Result(Str) readAllAlloc(Allocator ally, FILE *f) {
  Result(Str) res = alloc(ally, 16);
  if (!res.ok) {
    return res;
  }
  Str str = res.val;
  if (!str.ptr) {
    return Result_Err(Str, "could not allocate string");
  }
  size_t read = 0;
  size_t total_read = 0;
  while ((read = fread(str.ptr + total_read, 1, str.len - total_read, f))) {
    total_read += read;
    if (str.len <= total_read) {
      size_t new_len = str.len * 2;
      resizeAllocation(ally, &str, new_len);
      if (str.len != new_len) {
        return Result_Err(Str, "could not expand string");
      }
    }
  }
  resizeAllocation(ally, &str, total_read);
  return Result_Ok(Str, str);
}

#endif /* READ_ALL_ALLOC_H */
