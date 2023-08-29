#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#include "parser/codegen.c"
#include "parser/parser.c"
#include "parser/tokenizer.c"
#include "std/Allocator.c"
#include "std/panic.c"
#include "std/readFile.c"
#include "std/writeAll.c"

int main(int argc, char **argv, char **envp) {
  (void)envp;

  if (argc < 3) {
    panic("usage: bc [inputfile.bc] [outputfile.cmd]");
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
      // .realloc = (Realloc *)realloc,
      // .state = NULL,
      .realloc = bumpRealloc,
      .state = &state,
  };

  Result(Slice_char) res = readFile(ally, argv[1]);
  if (!res.ok) {
    fprintf(stderr, "Error: %s: %s\n", res.err, argv[1]);
    return 1;
  }
  Slice(char) data = res.val;

  fprintf(stdout, "---  SOURCE ---\n");
  writeAll(stdout, data);
  fprintf(stdout, "\n--- /SOURCE ---\n");

  fprintf(stdout, "---  TOKENS ---\n");

  TokenIterator it = tokenizer(data);
  Token t = nextToken(&it);

  while (t.type) {
    printToken(t);
    t = nextToken(&it);
  }

  fprintf(stdout, "\n--- /TOKENS ---\n");

  fprintf(stdout, "---  PARSE ---\n");
  resetTokenizer(&it);

  Program prog = parse(ally, &it);
  for (size_t i = 0; i < prog.statements.len; i++) {
    printStatement(prog.statements.ptr[i]);
  }

  fprintf(stdout, "--- /PARSE ---\n");

  fprintf(stdout, "---  CODEGEN ---\n");

  FILE *outputFile = fopen(argv[2], "w");
  outputBatch(prog, outputFile);
  fclose(outputFile);

  fprintf(stdout, "--- /CODEGEN ---\n");

  resizeAllocation(ally, char, &data, 0);

  return 0;
}
