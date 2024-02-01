#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "parser/codegen.c"
#include "parser/parser.c"
#include "parser/sema.c"
#include "parser/tokenizer.c"
#include "std/Allocator.c"

#include "std/panic.c"
#include "std/readFile.c"
#include "std/writeAll.c"

static void printSize(size_t bytes) {
  if (bytes >= 1024 * 1024) {
    printf("%.2fMiB", (double)bytes / (1024 * 1024));
    return;
  }
  if (bytes >= 1024) {
    printf("%.2fKiB", (double)bytes / 1024);
    return;
  }
  printf("%zuB", bytes);
}

static bool startsWith(char *haystack, char *needle) {
  while (*haystack && *needle) {
    if (*haystack++ != *needle++)
      return false;
  }
  return *needle == 0;
}

int main(int argc, char **argv, char **envp) {
  bool noColor = false;
  while (*envp) {
    char *str = *envp;
    if (startsWith(str, "NO_COLOR=") && strlen(str) >= 10)
      noColor = true;
    envp++;
  }
  char *gray = noColor ? "" : "\x1b[90m";
  char *red = noColor ? "" : "\x1b[91m";
  char *green = noColor ? "" : "\x1b[92m";
  char *yellow = noColor ? "" : "\x1b[93m";
  char *blue = noColor ? "" : "\x1b[94m";
  char *pink = noColor ? "" : "\x1b[95m";
  char *cyan = noColor ? "" : "\x1b[96m";
  char *reset = noColor ? "" : "\x1b[0m";

  if (argc < 3) {
    panic("usage: bc [inputfile.bb] [outputfile.cmd]");
  }

  char mem[1048576];
  Bump state = {
      .mem =
          {
              .ptr = mem,
              .len = 1048576,
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

  fprintf(stdout, "%s---  SOURCE ---%s\n", gray, blue);
  writeAll(stdout, data);
  fprintf(stdout, "\n%s--- /SOURCE ---\n", gray);

  fprintf(stdout, "---  TOKENS ---%s\n", green);
  fflush(stdout);

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
        fflush(stdout);
      } else {
        fprintf(stdout, "%s,\t%s", gray, green);
        fflush(stdout);
      }
    }
  }

  fprintf(stdout, "\n%s--- /TOKENS ---\n", gray);

  fprintf(stdout, "---  PARSE ---%s\n", yellow);

  fflush(stdout);

  resetTokenizer(&it);

  Program prog = parse(ally, &it);
  for (size_t i = 0; i < prog.statements.len; i++) {
    printStatement(prog.statements.ptr[i]);
  }

  fprintf(stdout, "%s--- /PARSE ---\n", gray);

  fprintf(stdout, "---  ANALYZE ---%s\n", red);
  fflush(stdout);
  analyze(ally, prog);
  fprintf(stdout, "%s--- /ANALYZE ---\n", gray);

  fprintf(stdout, "---  CODEGEN ---%s\n", pink);
  fflush(stdout);

  Result(Vec_char) outputVecRes = createVec(ally, char, 512);
  if (!outputVecRes.ok)
    panic(outputVecRes.err);
  Vec(char) outputVec = outputVecRes.val;
  outputBatch(prog, ally, &outputVec);
  FILE *outputFile = fopen(argv[2], "w");
  writeAll(outputFile, outputVec.slice);
  fclose(outputFile);
  fprintf(stdout, "%sOutput Batch stored in %s:%s\n\n", cyan, argv[2], reset);
  Result(Slice_char) outputRes = readFile(ally, argv[2]);
  if (!outputRes.ok) {
    panic(outputRes.err);
  }
  Slice(char) outputData = outputRes.val;
  fprintf(stdout, "%1.*s\n", (int)outputData.len, outputData.ptr);
  fprintf(stdout, "%s--- /CODEGEN ---\n", gray);

  fprintf(stdout, "%sMemory usage: ", cyan);
  fflush(stdout);
  printSize(state.cur);
  fprintf(stdout, " / ");
  fflush(stdout);
  printSize(state.mem.len);
  fprintf(stdout, "%s\n", reset);
  fflush(stdout);

  resizeAllocation(ally, char, &data, 0);

  return 0;
}
