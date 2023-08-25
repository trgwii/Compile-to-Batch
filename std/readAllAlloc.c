#ifndef READ_ALL_ALLOC_H
#define READ_ALL_ALLOC_H

#include "Result.h"
#include "Str.h"
#include "defs.h"
#include <stdio.h>

static Result(Str) readAllAlloc(FILE *f) {
  Str str = {.len = 16};
  str.ptr = malloc(str.len);
  if (!str.ptr) {
    return Result_Err(Str, "could not allocate string");
  }
  size_t read = 0;
  size_t total_read = 0;
  while ((read = fread(str.ptr + total_read, 1, str.len - total_read, f))) {
    total_read += read;
    if (str.len <= total_read) {
      size_t new_len = str.len * 2;
      char *new_ptr = realloc(str.ptr, new_len);
      if (!new_ptr) {
        return Result_Err(Str, "could not expand string");
      }
      str = (Str){
          .ptr = new_ptr,
          .len = new_len,
      };
    }
  }
  str.len = total_read;
  char *final_ptr = realloc(str.ptr, total_read);
  if (final_ptr) {
    str.ptr = final_ptr;
  }
  return Result_Ok(Str, str);
}

#endif /* READ_ALL_ALLOC_H */
