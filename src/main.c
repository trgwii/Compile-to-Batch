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

static void printSize(size_t bytes) {
  if (bytes > 1024 * 1024) {
    printf("%.2fMiB", (double)bytes / (1024 * 1024));
    return;
  }
  if (bytes > 1024) {
    printf("%.2fKiB", (double)bytes / 1024);
    return;
  }
  printf("%luB", bytes);
}

int main(int argc, char **argv, char **envp) {
  (void)envp;

  if (argc < 3) {
    panic("usage: bc [inputfile.bb] [outputfile.cmd]");
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

  fprintf(stdout, "\x1b[90m---  SOURCE ---\x1b[94m\n");
  writeAll(stdout, data);
  fprintf(stdout, "\n\x1b[90m--- /SOURCE ---\n");

  fprintf(stdout, "---  TOKENS ---\x1b[92m\n");

  TokenIterator it = tokenizer(data);
  Token t = nextToken(&it);
  char nl = 0;
  while (t.type) {
    printToken(t);
    t = nextToken(&it);
    if (t.type) {
      if (++nl >= 4) {
        nl = 0;
        fprintf(stdout, "\n");
      } else {
        fprintf(stdout, "\x1b[90m,\t\x1b[92m");
      }
    }
  }

  fprintf(stdout, "\n\x1b[90m--- /TOKENS ---\n");

  fprintf(stdout, "---  PARSE ---\x1b[93m\n");
  resetTokenizer(&it);

  Program prog = parse(ally, &it);
  for (size_t i = 0; i < prog.statements.len; i++) {
    printStatement(prog.statements.ptr[i]);
  }

  fprintf(stdout, "\x1b[90m--- /PARSE ---\n");

  fprintf(stdout, "---  CODEGEN ---\x1b[95m\n");

  FILE *outputFile = fopen(argv[2], "w");
  outputBatch(prog, outputFile);
  fclose(outputFile);
  fprintf(stdout, "\x1b[96mOutput Batch stored in %s\n", argv[2]);
  fprintf(stdout, "\x1b[90m--- /CODEGEN ---\n");

  fprintf(stdout, "\x1b[96mMemory usage: ");
  printSize(state.cur);
  fprintf(stdout, " / ");
  printSize(state.mem.len);
  fprintf(stdout, "\x1b[0m\n");

  resizeAllocation(ally, char, &data, 0);

  return 0;
}
