#ifndef SLICE_H
#define SLICE_H

#include <stddef.h>

#define Slice(T) Slice_##T

#define DefSlice(T)                                                            \
  typedef struct {                                                             \
    T *ptr;                                                                    \
    size_t len;                                                                \
  } Slice(T)

#endif /* SLICE_H */
