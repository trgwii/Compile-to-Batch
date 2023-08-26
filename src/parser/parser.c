#include "../std/Allocator.c"
#include "tokenizer.c"

typedef enum {
  CallExpression,
  IdentifierExpression,
  NumericExpression,
  StringExpression,
} ExpressionType;

typedef struct Expression {
  ExpressionType type;
  union {
    struct {
      struct Expression *callee;
      struct Expression *parameters;
      size_t parameters_len;
    } call;
    Str number;
    Str string;
    Str identifier;
  };
} Expression;

DefSlice(Expression);

typedef enum {
  ExpressionStatement,
} StatementType;

typedef struct {
  StatementType type;
  union {
    Expression expression;
  };
} Statement;

typedef struct {
  Statement *statements;
  size_t statements_len;
} Program;

static inline Expression parseExpression(Allocator ally, TokenIterator *it,
                                         Token t) {
  fprintf(stdout, "parseExpr: ");
  printToken(t);
  switch (t.type) {
  case TokenType_Number:
    return (Expression){.type = NumericExpression, .number = t.number};
  case TokenType_String:
    return (Expression){.type = StringExpression, .string = t.string};
  case TokenType_Ident: {
    Token next = peekToken(it);
    if (next.type == TokenType_OpenParen) {
      // call expression
      nextToken(it);
      Result(Str) parameters_mem = alloc(ally, sizeof(Expression) * 16);
      if (!parameters_mem.ok) {
        panic(parameters_mem.err);
      }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-align"
      Slice(Expression)
          parameters = {.ptr = (Expression *)parameters_mem.val.ptr,
                        .len = parameters_mem.val.len / sizeof(Expression)};
#pragma clang diagnostic pop
      size_t parameters_len = 0;
      Token param = nextToken(it);
      while (param.type != TokenType_CloseParen) {
        if (param.type == TokenType_EOF) {
          panic("parseExpression: Unclosed open paren");
        }
        Token paramSep = nextToken(it);
        if (paramSep.type != TokenType_Comma &&
            paramSep.type != TokenType_CloseParen) {
          printToken(paramSep);
          panic("parseExpression: Parameter list expression not followed by "
                "comma or close paren ^");
        }
        if (parameters_len >= parameters.len) {
          resizeAllocation(ally, (Str *)&parameters, parameters.len * 2);
          if (parameters_len >= parameters.len) {
            panic("parseExpression: Failed to extend parameter list");
          }
        }
        parameters.ptr[parameters_len++] = parseExpression(ally, it, param);
        param = nextToken(it);
      }
      resizeAllocation(ally, (Str *)&parameters, parameters_len);

      Result(Str) callee_res = alloc(ally, sizeof(Expression));
      if (!callee_res.ok) {
        panic("parseExpression: Failed to allocate callee");
      }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-align"
      Expression *callee = (Expression *)callee_res.val.ptr;
#pragma clang diagnostic pop
      *callee = (Expression){
          .type = IdentifierExpression,
          .identifier = t.ident,
      };

      fprintf(stdout, "CallExpression\n");
      return (Expression){.type = CallExpression,
                          .call = {.callee = callee,
                                   .parameters = parameters.ptr,
                                   parameters_len = parameters.len}};
    }
    // identifier expression
    return (Expression){.type = IdentifierExpression, .identifier = t.ident};
  }
  case TokenType_EOF:
  case TokenType_OpenParen:
  case TokenType_CloseParen:
  case TokenType_Semi:
  case TokenType_Comma:
  case TokenType_Unknown: {
    printToken(t);
    panic("parseExpression: Invalid TokenType ^");
  }
  }
}

static Program parse(Allocator ally, TokenIterator *it) {
  Result(Str) res = alloc(ally, sizeof(Statement) * 16);
  if (!res.ok) {
    panic("parse: Failed to alloc statements");
  }
  size_t statements_len = 0;
  Str statements = res.val;
  Token t = nextToken(it);

  while (t.type) {

    if (t.type == TokenType_Ident || t.type == TokenType_Number ||
        t.type == TokenType_String) {
      if (statements_len >= statements.len) {
        resizeAllocation(ally, &statements, statements.len * 2);
        if (statements_len >= statements.len) {
          panic("parse: Failed to expand statements");
        }
      }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-align"
      ((Statement *)statements.ptr)[statements_len++] = (Statement){
          .type = ExpressionStatement,
          .expression = parseExpression(ally, it, t),
      };
#pragma clang diagnostic pop
      Token semi = nextToken(it);
      if (semi.type != TokenType_Semi) {
        printToken(semi);
        panic("parse: Unknown token following expression statement ^");
      }
    }

    t = nextToken(it);
  }
  return (Program){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-align"
      .statements = (Statement *)statements.ptr,
#pragma clang diagnostic pop
      .statements_len = statements.len / sizeof(Statement),
  };
}
