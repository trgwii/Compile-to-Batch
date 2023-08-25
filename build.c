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

            // Weird Windows thing
             " -Wno-used-but-marked-unused"

             // " -Wno-error=unused-variable"

            #ifdef _WIN32
             " -o bc.exe"
             #else
             " -o bc"
             #endif
             " main.c"))
    exit(1);
  #ifdef _WIN32
  if (system("bc main.bb"))
  #else
  if (system("./bc main.bb"))
  #endif
    exit(1);
}