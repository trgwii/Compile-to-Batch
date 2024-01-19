#ifndef EQL_H
#define EQL_H

#include "Slice.h"
#include "defs.h"
#include <stdbool.h>

#ifdef BUILDING_WITH_ZIG
extern bool eql(Slice(char) a, Slice(char) b);
#else
static bool eql(Slice(char) a, Slice(char) b) {
  if (a.len != b.len)
    return false;
  if (a.ptr == b.ptr)
    return true;
  for (size_t i = 0; i < a.len; i++) {
    if (a.ptr[i] != b.ptr[i])
      return false;
  }
  return true;
}
#endif

#endif /* EQL_H */
