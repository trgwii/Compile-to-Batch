#ifndef READ_ALL_ALLOC_H
#define READ_ALL_ALLOC_H

#include "Allocator.c"
#include "Result.h"
#include "defs.h"
#include <stdio.h>

static Result(Slice_char) readAllAlloc(Allocator ally, FILE *f) {
  Result(Slice_char) res = alloc(ally, char, 16);
  if (!res.ok) {
    return res;
  }
  Slice_char str = res.val;
  if (!str.ptr) {
    return Result_Err(Slice_char, "could not allocate string");
  }
  size_t read = 0;
  size_t total_read = 0;
  while ((read = fread(str.ptr + total_read, 1, str.len - total_read, f))) {
    total_read += read;
    if (str.len <= total_read) {
      size_t new_len = str.len * 2;
      resizeAllocation(ally, char, &str, new_len);
      if (str.len != new_len) {
        return Result_Err(Slice_char, "could not expand string");
      }
    }
  }
  resizeAllocation(ally, char, &str, total_read);
  return Result_Ok(Slice_char, str);
}

#endif /* READ_ALL_ALLOC_H */
