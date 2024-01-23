#ifdef BUILDING_WITH_ZIG
#undef BUILDING_WITH_ZIG
#include "src/std/eql.c"
#define BUILDING_WITH_ZIG
#else
#include "src/std/eql.c"
#endif
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
#ifdef BUILDING_WITH_ZIG
  if (system("zig build"))
    exit(1);
#endif
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
             " -o " OUT
#ifdef BUILDING_WITH_ZIG
             " -DBUILDING_WITH_ZIG"
#ifdef _WIN32
             " zig-out/lib/bc.lib"
#else
             " zig-out/lib/libbc.a"
#endif
#endif
             " src/main.c"))
    exit(1);
  if (releaseMode(argc, argv)) {
#ifdef BUILDING_WITH_ZIG
    if (system("zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows"))
      exit(1);
#endif
    if (system("zig cc"
               " -O2"
               " -target x86_64-windows"
               " -Wno-single-bit-bitfield-constant-conversion"
               " -o bin/bc.exe"
#ifdef BUILDING_WITH_ZIG
               " -DBUILDING_WITH_ZIG"
               " zig-out/lib/bc.lib"
#endif

               " src/main.c"))
      exit(1);
#ifdef BUILDING_WITH_ZIG
    if (system("zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl"))
      exit(1);
#endif
    if (system("zig cc"
               " -O2"
               " -target x86_64-linux-musl"
               " -o bin/bc"
#ifdef BUILDING_WITH_ZIG
               " -DBUILDING_WITH_ZIG"
               " zig-out/lib/libbc.a"
#endif

               " src/main.c"))
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
