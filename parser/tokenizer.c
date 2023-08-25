#include "../std/Str.h"
#include <ctype.h>
#include <stddef.h>

typedef struct {
  Str data;
  size_t idx;
  size_t line;
  size_t col;
} TokenIterator;

typedef enum {
  TokenType_EOF = 0,
  TokenType_Ident,
  TokenType_Unknown,
} TokenType;

typedef struct {
  TokenType type;
  union {
    Str ident;
    struct {
      size_t line;
      size_t col;
      char c;
    } unknown;
  };
} Token;

static void printToken(Token t) {
  switch (t.type) {
  case TokenType_EOF: {
    printf("(eof)\n");
  } break;
  case TokenType_Ident: {
    printf("Ident(\"%1.*s\")\n", (int)t.ident.len, t.ident.ptr);
  } break;
  case TokenType_Unknown: {
    printf("(unknown:%d:%d: '%c')\n", (int)t.unknown.line, (int)t.unknown.col,
           t.unknown.c);
  } break;
  }
}

static void updateLocationInfo(TokenIterator *it, char c) {
  if (c == '\n') {
    it->col = 0;
    it->line++;
  } else {
    it->col++;
  }
}

static Token nextToken(TokenIterator *it) {
  if (it->idx >= it->data.len) {
    return (Token){.type = TokenType_EOF};
  }
  char *c = &it->data.ptr[it->idx++];
  updateLocationInfo(it, *c);
  while (isblank(*c) || *c == '\n') {
    if (it->idx >= it->data.len) {
      return (Token){.type = TokenType_EOF};
    }
    c = &it->data.ptr[it->idx++];
    updateLocationInfo(it, *c);
  }
  if (isalpha(*c)) {
    char *start = c;
    while (isalpha(*c)) {
      if (it->idx > it->data.len) {
        break;
      }
      c = &it->data.ptr[it->idx++];
      updateLocationInfo(it, *c);
    }
    return (Token){.type = TokenType_Ident,
                   .ident = {
                       .ptr = start,
                       .len = (size_t)c - (size_t)start,
                   }};
  }
  return (Token){.type = TokenType_Unknown,
                 .unknown = {
                     .line = it->line,
                     .col = it->col,
                     .c = *c,
                 }};
}
