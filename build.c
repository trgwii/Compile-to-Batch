#include <stdlib.h>

#ifdef _WIN32
#define OUT "bin\\bc.exe"
#else
#define OUT "./bin/bc"
#endif

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

#ifdef _WIN32
             // Weird Windows thing
             " -Wno-used-but-marked-unused"
#endif
             " -o " OUT " src/main.c"))
    exit(1);
  if (system(OUT " main.bb"))
    exit(1);
}
