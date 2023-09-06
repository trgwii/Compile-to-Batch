#ifndef TOKENIZER_H
#define TOKENIZER_H

#include "../std/defs.h"
#include "../std/eql.c"
#include "../std/panic.c"
#include <ctype.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct {
  Slice(char) data;
  size_t cur;
  size_t line;
  size_t col;
} TokenIterator;

static TokenIterator tokenizer(Slice(char) data) {
  return (TokenIterator){.data = data, .cur = 0, .line = 1, .col = 1};
}

typedef enum {
  TokenType_EOF = 0,
  TokenType_Ident,
  TokenType_Number,
  TokenType_OpenParen,
  TokenType_CloseParen,
  TokenType_OpenCurly,
  TokenType_CloseCurly,
  TokenType_Semi,
  TokenType_Comma,
  TokenType_String,
  TokenType_Colon,
  TokenType_Equal,
  TokenType_Excl,
  TokenType_Star,
  TokenType_Plus,
  TokenType_Hyphen,
  TokenType_Slash,
  TokenType_InlineBatch,
  TokenType_Unknown,
} TokenType;

typedef struct {
  TokenType type;
  union {
    Slice(char) ident;
    Slice(char) number;
    Slice(char) string;
    Slice(char) inline_batch;
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
    printf("(eof)");
  } break;
  case TokenType_Ident: {
    printf("Ident(%1.*s)", (int)t.ident.len, t.ident.ptr);
  } break;
  case TokenType_Number: {
    printf("Number(%1.*s)", (int)t.number.len, t.number.ptr);
  } break;
  case TokenType_OpenParen: {
    printf("OpenParen");
  } break;
  case TokenType_CloseParen: {
    printf("CloseParen");
  } break;
  case TokenType_OpenCurly: {
    printf("OpenCurly");
  } break;
  case TokenType_CloseCurly: {
    printf("CloseCurly");
  } break;
  case TokenType_Semi: {
    printf("Semi");
  } break;
  case TokenType_Comma: {
    printf("Comma");
  } break;
  case TokenType_String: {
    printf("String(\"%1.*s\")", (int)t.string.len, t.string.ptr);
  } break;
  case TokenType_Colon: {
    printf("Colon");
  } break;
  case TokenType_Equal: {
    printf("Equal");
  } break;
  case TokenType_Excl: {
    printf("Excl");
  } break;
  case TokenType_Star: {
    printf("Star");
  } break;
  case TokenType_Plus: {
    printf("Plus");
  } break;
  case TokenType_Hyphen: {
    printf("Hyphen");
  } break;
  case TokenType_Slash: {
    printf("Slash");
  } break;
  case TokenType_InlineBatch: {
    printf("Batch {%1.*s}", (int)t.inline_batch.len, t.inline_batch.ptr);
  } break;
  case TokenType_Unknown: {
    printf("(unknown:%d:%d: '%c')", (int)t.unknown.line, (int)t.unknown.col,
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

static bool tokenizerEnded(TokenIterator *it) {
  return it->cur >= it->data.len;
}

static void resetTokenizer(TokenIterator *it) {
  it->cur = 0;
  it->line = 1;
  it->col = 1;
}

static char nextChar(TokenIterator *it) {
  char c = it->data.ptr[it->cur++];
  updateLocationInfo(it, c);
  return c;
}

static char skipWhitespace(TokenIterator *it, char c) {
  while (isblank(c) || isspace(c)) {
    if (tokenizerEnded(it)) {
      return 0;
    }
    c = nextChar(it);
  }
  return c;
}

static Token nextToken(TokenIterator *it) {
  if (tokenizerEnded(it)) {
    return (Token){.type = TokenType_EOF};
  }
  char c = nextChar(it);

  // skip whitespace
  c = skipWhitespace(it, c);
  if (c == 0) {
    return (Token){.type = TokenType_EOF};
  }

  // size_t start_cur = it->cur;

  // char buf[16384];
  // for (size_t i = 0; i < it->data.len; i++) {
  //   buf[i] = it->data.ptr[i];
  //   if (buf[i] == '\n' || buf[i] == '\r')
  //     buf[i] = ' ';
  // }
  // fprintf(stdout, "\x1b[90m%1.*s\x1b[0m\n", (int)it->data.len, buf);
  // for (size_t i = 0; i < start_cur - 1; i++) {
  //   fprintf(stdout, " ");
  // }
  // fprintf(stdout, "\x1b[93m^\x1b[0m\n");

  switch (c) {
  case '(':
    return (Token){.type = TokenType_OpenParen};
  case ')':
    return (Token){.type = TokenType_CloseParen};
  case '{':
    return (Token){.type = TokenType_OpenCurly};
  case '}':
    return (Token){.type = TokenType_CloseCurly};
  case ';':
    return (Token){.type = TokenType_Semi};
  case ',':
    return (Token){.type = TokenType_Comma};
  case ':':
    return (Token){.type = TokenType_Colon};
  case '=':
    return (Token){.type = TokenType_Equal};
  case '!':
    return (Token){.type = TokenType_Excl};
  case '*':
    return (Token){.type = TokenType_Star};
  case '+':
    return (Token){.type = TokenType_Plus};
  case '-':
    return (Token){.type = TokenType_Hyphen};
  case '/':
    return (Token){.type = TokenType_Slash};
  }

  // keywords / identifiers
  if (isalpha(c) || c == '_') {
    size_t start = it->cur - 1;
    while (c == '_' || isalpha(c) || isdigit(c)) {
      if (tokenizerEnded(it)) {
        break;
      }
      c = nextChar(it);
    }
    it->cur--;

    Slice(char) ident = {
        .ptr = it->data.ptr + start,
        .len = it->cur - start,
    };

    if (eql(ident, (Slice(char)){.ptr = "batch", .len = 5})) {
      it->cur++;
      c = skipWhitespace(it, c);
      if (c == 0) {
        return (Token){.type = TokenType_EOF};
      }
      if (c != '{') {
        panic("batch keyword not followed by {");
      }
      size_t bracket_len = 0;
      while (c == '{') {
        c = nextChar(it);
        if (tokenizerEnded(it)) {
          return (Token){.type = TokenType_EOF};
        }
        bracket_len += 1;
      }
      size_t body_start = it->cur - 1;
      while (true) {
        c = nextChar(it);
        if (tokenizerEnded(it)) {
          return (Token){
              .type = TokenType_InlineBatch,
              .inline_batch =
                  {
                      .ptr = it->data.ptr + body_start,
                      .len = it->cur - body_start - bracket_len,
                  },
          };
        }
        if (c == '}') {
          bool ended = true;
          for (size_t i = 0; i < bracket_len - 1; i++) {
            c = nextChar(it);
            if (tokenizerEnded(it)) {
              return (Token){
                  .type = TokenType_InlineBatch,
                  .inline_batch =
                      {
                          .ptr = it->data.ptr + body_start,
                          .len = it->cur - body_start - bracket_len,
                      },
              };
            }
            if (c != '}') {
              ended = false;
            }
          }
          if (ended) {
            return (Token){
                .type = TokenType_InlineBatch,
                .inline_batch =
                    {
                        .ptr = it->data.ptr + body_start,
                        .len = it->cur - body_start - bracket_len,
                    },
            };
          }
        }
      }
    }

    return (Token){.type = TokenType_Ident, .ident = ident};
  }

  // numeric literal
  if (isdigit(c)) {
    size_t start = it->cur - 1;
    while (isdigit(c)) {
      if (tokenizerEnded(it)) {
        break;
      }
      c = nextChar(it);
    }
    it->cur--;
    return (Token){.type = TokenType_Number,
                   .number = {
                       .ptr = it->data.ptr + start,
                       .len = it->cur - start,
                   }};
  }

  if (c == '"') {
    size_t start = it->cur;
    bool escape = false;
    do {
      if (tokenizerEnded(it)) {
        panic("Tokenizer: Unterminated string literal");
      }
      c = nextChar(it);
      if (escape) {
        if (tokenizerEnded(it)) {
          panic("Tokenizer: Unterminated string literal");
        }
        c = nextChar(it);
        escape = false;
      } else if (c == '\\') {
        escape = true;
      }
    } while (escape || c != '"');

    return (Token){.type = TokenType_String,
                   .string = {
                       .ptr = it->data.ptr + start,
                       .len = it->cur - 1 - start,
                   }};
  }

  return (Token){.type = TokenType_Unknown,
                 .unknown = {
                     .line = it->line,
                     .col = it->col,
                     .c = c,
                 }};
}

static Token peekToken(TokenIterator *it) {
  size_t cur = it->cur;
  size_t line = it->line;
  size_t col = it->col;
  Token t = nextToken(it);
  it->cur = cur;
  it->line = line;
  it->col = col;
  return t;
}

#endif /* TOKENIZER_H */
