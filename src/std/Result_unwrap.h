#ifndef RESULT_UNWRAP_H
#define RESULT_UNWRAP_H

#include "panic.c"

#define Result_unwrap(T, result)                                               \
  (result.ok ? result.val : (panic(result.err), result.val))

#endif /* RESULT_UNWRAP_H */
