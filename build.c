#include <stdlib.h>

int main(void) {
  if (system("zig cc"
             " -Wall"
             " -Wextra"
             " -Wpedantic"
             " -Weverything"
             " -Werror"

             " -Wno-padded"
             " -Wno-declaration-after-statement"
             " -Wno-unsafe-buffer-usage"

             // " -Wno-error=unused-variable"

             " -o bc"
             " main.c"))
    exit(1);
  if (system("./bc main.bb"))
    exit(1);
}