#ifndef PANIC_H
#define PANIC_H

#include <stdio.h>
#include <stdlib.h>

#ifdef BUILDING_WITH_ZIG
extern __attribute__((noreturn)) void panic(const char *msg);
#else
__attribute__((noreturn)) static void panic(const char *msg) {
  fflush(stdout);
  fprintf(stderr, "%s\n", msg);
  exit(1);
}
#endif

#endif /* PANIC_H */
