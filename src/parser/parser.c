#include "../std/Allocator.c"
#include "../std/Vec.c"
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
    Slice(char) number;
    Slice(char) string;
    Slice(char) identifier;
  };
} Expression;

DefSlice(Expression);
DefResult(Slice_Expression);
DefVec(Expression);
DefResult(Vec_Expression);

typedef enum {
  ExpressionStatement,
} StatementType;

typedef struct {
  StatementType type;
  union {
    Expression expression;
  };
} Statement;

DefSlice(Statement);
DefResult(Slice_Statement);
DefVec(Statement);
DefResult(Vec_Statement);

typedef struct {
  Slice(Statement) statements;
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
      Result(Vec_Expression) res = createVec(ally, Expression, 16);
      if (!res.ok) {
        panic(res.err);
      }
      Vec(Expression) parameters = res.val;
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
        Expression expr = parseExpression(ally, it, param);
        if (!appendToVec(&parameters, Expression, &expr)) {
          panic("Failed to append to parameter list");
        }
        param = nextToken(it);
      }
      shrinkToLength(&parameters, Expression);

      Result(Slice_Expression) callee_res = alloc(ally, Expression, 1);
      if (!callee_res.ok) {
        panic("parseExpression: Failed to allocate callee");
      }
      Expression *callee = callee_res.val.ptr;
      *callee = (Expression){
          .type = IdentifierExpression,
          .identifier = t.ident,
      };

      fprintf(stdout, "CallExpression\n");
      return (Expression){.type = CallExpression,
                          .call = {.callee = callee,
                                   .parameters = parameters.slice.ptr,
                                   .parameters_len = parameters.slice.len}};
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
  Result(Vec_Statement) res = createVec(ally, Statement, 16);
  if (!res.ok) {
    panic("parse: Failed to alloc statements");
  }
  Vec(Statement) statements = res.val;
  Token t = nextToken(it);

  while (t.type) {

    if (t.type == TokenType_Ident || t.type == TokenType_Number ||
        t.type == TokenType_String) {
      Statement s = {
          .type = ExpressionStatement,
          .expression = parseExpression(ally, it, t),
      };
      if (!appendToVec(&statements, Statement, &s)) {
        panic("Failed to append to statement list");
      }
      Token semi = nextToken(it);
      if (semi.type != TokenType_Semi) {
        printToken(semi);
        panic("parse: Unknown token following expression statement ^");
      }
    }

    t = nextToken(it);
  }
  shrinkToLength(&statements, Statement);
  return (Program){.statements = statements.slice};
}
