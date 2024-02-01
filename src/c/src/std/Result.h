#ifndef RESULT_H
#define RESULT_H

#include <stdbool.h>

#define Result(T) Result_##T

#define Result_Ok(T, value)                                                    \
  (Result(T)) { .val = value, .ok = true }

#define Result_Err(T, error)                                                   \
  (Result(T)) { .err = error, .ok = false }

#define DefResult(T)                                                           \
  typedef struct {                                                             \
    union {                                                                    \
      T val;                                                                   \
      char *err;                                                               \
    };                                                                         \
    bool ok;                                                                   \
  } Result(T)

#endif /* RESULT_H */
