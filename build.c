#include "src/std/eql.c"
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define OUT "bin\\bc.exe"
#else
#define OUT "./bin/bc"
#endif

bool releaseMode(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    if (eql((Slice(char)){.ptr = argv[i], .len = strlen(argv[i])},
            (Slice(char)){.ptr = "release", .len = 7})) {
      return true;
    }
  }
  return false;
}

int main(int argc, char **argv) {
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
  if (releaseMode(argc, argv)) {
    if (system("zig cc"
               " -O2"
               " -target x86_64-windows"
               " -Wno-single-bit-bitfield-constant-conversion"
               " -o bin/bc.exe src/main.c"))
      exit(1);
    if (system("zig cc"
               " -O2"
               " -target x86_64-linux-musl"
               " -o bin/bc src/main.c"))
      exit(1);
  }
  if (system(OUT " main.bb main.cmd"))
    exit(1);
#ifdef _WIN32
  if (system("cmd.exe /c main.cmd"))
    exit(1);
#else
  if (releaseMode(argc, argv))
    system("ls -lh bin");
#endif
}
