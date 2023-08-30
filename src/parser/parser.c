#ifndef PARSER_H
#define PARSER_H

#include "../std/Allocator.c"
#include "../std/Vec.c"
#include "tokenizer.c"

typedef enum {
  CallExpression,
  IdentifierExpression,
  NumericExpression,
  StringExpression,
  ArithmeticExpression,
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
    struct {
      char op;
      struct Expression *left;
      struct Expression *right;
    } arithmetic;
  };
} Expression;

DefSlice(Expression);
DefResult(Slice_Expression);
DefVec(Expression);
DefResult(Vec_Expression);

typedef struct {
  Slice(char) name;
  Expression value;
  bool constant;
} Declaration;

typedef struct {
  Slice(char) name;
  Expression value;
} Assignment;

typedef enum {
  ExpressionStatement,
  DeclarationStatement,
  AssignmentStatement,
} StatementType;

typedef struct {
  StatementType type;
  union {
    Expression expression;
    Declaration declaration;
    Assignment assignment;
  };
} Statement;

DefSlice(Statement);
DefResult(Slice_Statement);
DefVec(Statement);
DefResult(Vec_Statement);

static void printExpression(Expression expr) {
  fprintf(stdout, "Expr:");
  switch (expr.type) {
  case CallExpression: {
    fprintf(stdout, "Call:(");
    printExpression(*expr.call.callee);
    fprintf(stdout, ") with (");
    if (expr.call.parameters_len > 0) {
      printExpression(expr.call.parameters[0]);
    }
    for (size_t i = 1; i < expr.call.parameters_len; i++) {
      fprintf(stdout, ", ");
      printExpression(expr.call.parameters[i]);
    }
    fprintf(stdout, ")");
  } break;
  case IdentifierExpression: {
    fprintf(stdout, "Ident(%1.*s)", (int)expr.identifier.len,
            expr.identifier.ptr);
  } break;
  case NumericExpression: {
    fprintf(stdout, "Number(%1.*s)", (int)expr.number.len, expr.number.ptr);
  } break;
  case StringExpression: {
    fprintf(stdout, "String(\"%1.*s\")", (int)expr.string.len, expr.string.ptr);
  } break;
  case ArithmeticExpression: {

    fprintf(stdout, "Arith(");
    printExpression(*expr.arithmetic.left);
    fprintf(stdout, " %c ", expr.arithmetic.op);
    printExpression(*expr.arithmetic.right);
    fprintf(stdout, ")");
  } break;
  }
}

static void printStatement(Statement stmt) {
  switch (stmt.type) {
  case ExpressionStatement: {
    Expression expr = stmt.expression;
    printExpression(expr);
    fprintf(stdout, "\n");
  } break;
  case DeclarationStatement: {
    Declaration decl = stmt.declaration;
    fprintf(stdout, "%1.*s :%c ", (int)decl.name.len, decl.name.ptr,
            decl.constant ? ':' : '=');
    printExpression(decl.value);
    fprintf(stdout, "\n");
  } break;
  case AssignmentStatement: {
    Assignment assign = stmt.assignment;
    fprintf(stdout, "%1.*s = ", (int)assign.name.len, assign.name.ptr);
    printExpression(assign.value);
    fprintf(stdout, "\n");
  } break;
  }
}

typedef struct {
  Slice(Statement) statements;
} Program;

static inline Expression parseExpression(Allocator ally, TokenIterator *it,
                                         Token t) {
  switch (t.type) {
  case TokenType_Number: {
    Token next = peekToken(it);
    if (next.type == TokenType_Star || next.type == TokenType_Plus ||
        next.type == TokenType_Hyphen || next.type == TokenType_Slash) {
      nextToken(it);
      Result(Slice_Expression) lr_res = alloc(ally, Expression, 2);
      if (!lr_res.ok)
        panic(lr_res.err);
      Expression *left = &lr_res.val.ptr[0];
      Expression *right = &lr_res.val.ptr[1];
      *left = (Expression){
          .type = NumericExpression,
          .number = t.number,
      };
      *right = parseExpression(ally, it, nextToken(it));
      return (Expression){
          .type = ArithmeticExpression,
          .arithmetic =
              {
                  .op = next.type == TokenType_Star     ? '*'
                        : next.type == TokenType_Plus   ? '+'
                        : next.type == TokenType_Hyphen ? '-'
                                                        : '/',
                  .left = left,
                  .right = right,
              },
      };
    }
    return (Expression){.type = NumericExpression, .number = t.number};
  }
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
          panic("parseExpression: Parameter list expression not followed by "
                "comma or close paren ^");
        }

        Expression expr = parseExpression(ally, it, param);
        if (!appendToVec(&parameters, Expression, &expr)) {
          panic("Failed to append to parameter list");
        }
        if (paramSep.type == TokenType_CloseParen) {
          break;
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
  case TokenType_Colon:
  case TokenType_Equal:
  case TokenType_Star:
  case TokenType_Plus:
  case TokenType_Hyphen:
  case TokenType_Slash:
  case TokenType_Unknown: {
    printToken(t);
    panic("\nparseExpression: Invalid TokenType ^");
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
      if (t.type == TokenType_Ident && peekToken(it).type == TokenType_Colon) {
        nextToken(it); // :
        Token afterColon = peekToken(it);
        if (afterColon.type != TokenType_Equal &&
            afterColon.type != TokenType_Colon) {
          printToken(peekToken(it));
          panic("Invalid token following colon ^");
        }
        nextToken(it); // =
        Expression value = parseExpression(ally, it, nextToken(it));

        Statement decl_stmt = {
            .type = DeclarationStatement,
            .declaration = {.name = t.ident,
                            .value = value,
                            .constant = afterColon.type == TokenType_Colon},
        };
        if (!appendToVec(&statements, Statement, &decl_stmt)) {
          panic("Failed to append decl to statement list");
        }
      } else if (t.type == TokenType_Ident &&
                 peekToken(it).type == TokenType_Equal) {
        nextToken(it);
        Expression value = parseExpression(ally, it, nextToken(it));

        Statement assign_stmt = {
            .type = AssignmentStatement,
            .assignment = {.name = t.ident, .value = value},
        };
        if (!appendToVec(&statements, Statement, &assign_stmt)) {
          panic("Failed to append decl to statement list");
        }

      } else {
        Statement s = {
            .type = ExpressionStatement,
            .expression = parseExpression(ally, it, t),
        };
        if (!appendToVec(&statements, Statement, &s)) {
          panic("Failed to append to statement list");
        }
      }
      Token semi = nextToken(it);
      if (semi.type != TokenType_Semi) {
        printToken(semi);
        panic("\nparse: Unknown token following expression statement ^");
      }
    }

    t = nextToken(it);
  }
  shrinkToLength(&statements, Statement);
  return (Program){.statements = statements.slice};
}

#endif /* PARSER_H */
