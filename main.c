#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include "parser/tokenizer.c"
#include "std/Result_unwrap.h"
#include "std/readFile.c"
#include "std/Allocator.c"
#include "std/writeAll.c"

int main(int argc, char **argv, char **envp) {
  (void)envp;

  if (argc < 2) {
    fprintf(stderr, "usage: bc [file]\n");
    return 1;
  }

  char mem[16384];
  Bump state = {
    .mem = {
      .ptr = mem,
      .len = 16384,
    },
    .cur = 0,
  };
  Allocator ally = {
    .realloc = bumpRealloc,
    .state = &state,
  };

  Result(Str) res = readFile(ally, argv[1]);
  Str data = Result_unwrap(Str, res);

  fprintf(stdout, "---  SOURCE ---\n");
  writeAll(stdout, data);
  fprintf(stdout, "\n--- /SOURCE ---\n");

  fprintf(stdout, "---  TOKENS ---\n");

  TokenIterator it = {.data = data, .cur = 0, .line = 1, .col = 1};
  Token t = nextToken(&it);

  while (t.type) {
    printToken(t);
    t = nextToken(&it);
  }

  fprintf(stdout, "\n--- /TOKENS ---\n");

  data = resizeAllocation(ally, data, 0);

  return 0;
}
