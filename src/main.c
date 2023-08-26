#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include "parser/parser.c"
#include "parser/tokenizer.c"
#include "std/Allocator.c"
#include "std/panic.c"
#include "std/readFile.c"
#include "std/writeAll.c"

int main(int argc, char **argv, char **envp) {
  (void)envp;

  if (argc < 2) {
    panic("usage: bc [file]");
  }

  char mem[16384];
  Bump state = {
      .mem =
          {
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
  if (!res.ok) {
    fprintf(stderr, "Error: %s: %s\n", res.err, argv[1]);
    return 1;
  }
  Str data = res.val;

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

  fprintf(stdout, "---  PARSE ---\n");
  resetTokenizer(&it);

  parse(ally, &it);

  fprintf(stdout, "--- /PARSE ---\n");

  resizeAllocation(ally, &data, 0);

  return 0;
}
