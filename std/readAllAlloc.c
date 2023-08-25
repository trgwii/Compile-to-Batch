#ifndef READ_ALL_ALLOC_H
#define READ_ALL_ALLOC_H

#include "Result.h"
#include "Str.h"
#include "defs.h"
#include "Allocator.c"
#include <stdio.h>

static Result(Str) readAllAlloc(Allocator ally, FILE *f) {
  Str str = alloc(ally, 16);
  if (!str.ptr) {
    return Result_Err(Str, "could not allocate string");
  }
  size_t read = 0;
  size_t total_read = 0;
  while ((read = fread(str.ptr + total_read, 1, str.len - total_read, f))) {
    total_read += read;
    if (str.len <= total_read) {
      size_t new_len = str.len * 2;
      Str new_str = resizeAllocation(ally, str, new_len);
      if (!new_str.ptr) {
        return Result_Err(Str, "could not expand string");
      }
      str = new_str;
    }
  }
  Str final_str = resizeAllocation(ally, str, total_read);
  if (final_str.ptr) {
    str = final_str;
  }
  return Result_Ok(Str, str);
}

#endif /* READ_ALL_ALLOC_H */
