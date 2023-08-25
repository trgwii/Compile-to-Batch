#ifndef PANIC_H
#define PANIC_H

#include <stdio.h>
#include <stdlib.h>

__attribute__((noreturn)) static void panic(const char *msg) {
  printf("%s\n", msg);
  exit(1);
}

#endif /* PANIC_H */
