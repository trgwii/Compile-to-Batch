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
  StatementEOF = 0,
  ExpressionStatement,
  DeclarationStatement,
  AssignmentStatement,
  InlineBatchStatement,
  BlockStatement,
  IfStatement,
} StatementType;

typedef struct If If;
typedef struct Block Block;

typedef struct {
  StatementType type;
  union {
    Expression expression;
    Declaration declaration;
    Assignment assignment;
    Slice(char) inline_batch;
    If *if_statement;
    Block *block;
  };
} Statement;

DefSlice(Statement);
DefResult(Slice_Statement);
DefVec(Statement);
DefResult(Vec_Statement);

struct If {
  Expression condition;
  Statement *consequence;
  Statement *alternate;
};

DefSlice(If);
DefResult(Slice_If);

struct Block {
  Slice(Statement) statements;
};

DefSlice(Block);
DefResult(Slice_Block);

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
  case InlineBatchStatement: {
    fprintf(stdout, "Inline Batch {\n");
    fprintf(stdout, "%1.*s", (int)stmt.inline_batch.len, stmt.inline_batch.ptr);
    fprintf(stdout, "}\n");
  } break;
  case IfStatement: {
    fprintf(stdout, "If (");
    printExpression(stmt.if_statement->condition);
    fprintf(stdout, ") ");
    printStatement(*stmt.if_statement->consequence);
    if (stmt.if_statement->alternate) {
      fprintf(stdout, " else ");
      printStatement(*stmt.if_statement->alternate);
    }
  } break;
  case BlockStatement: {
    fprintf(stdout, "Block {\n");
    for (size_t i = 0; i < stmt.block->statements.len; i++) {
      printStatement(stmt.block->statements.ptr[i]);
    }
    fprintf(stdout, "}\n");
  } break;
  case StatementEOF: {
    panic("StatementEOF");
  } break;
  }
}

typedef struct {
  Slice(Statement) statements;
} Program;

// static Expression parseUnitExpression(Allocator ally, TokenIterator *it,
//                                       Token t) {}

static inline Expression parseExpression(Allocator ally, TokenIterator *it,
                                         Token t) {
  switch (t.type) {
  case TokenType_Number: {
    Token next = peekToken(it);
    if (next.type != TokenType_Star && next.type != TokenType_Plus &&
        next.type != TokenType_Hyphen && next.type != TokenType_Slash &&
        next.type != TokenType_Equal) {
      return (Expression){.type = NumericExpression, .number = t.number};
    }
    if (nextToken(it).type == TokenType_Equal) { // op
      if (peekToken(it).type != TokenType_Equal) {
        panic("Invalid expression following <num> =");
      }
      // ==
      //  ^
      nextToken(it);
    }

    Result(Slice_Expression) lr_res = alloc(ally, Expression, 2);
    if (!lr_res.ok)
      panic(lr_res.err);
    Expression *left = &lr_res.val.ptr[0];
    Expression *right = &lr_res.val.ptr[1];
    *left = parseExpression(ally, it, t);
    *right = parseExpression(ally, it, nextToken(it));
    return (Expression){
        .type = ArithmeticExpression,
        .arithmetic =
            {
                .op = next.type == TokenType_Star     ? '*'
                      : next.type == TokenType_Plus   ? '+'
                      : next.type == TokenType_Hyphen ? '-'
                      : next.type == TokenType_Equal  ? '=' // comparison
                                                      : '/',
                .left = left,
                .right = right,
            },
    };
  }
  case TokenType_String:
    return (Expression){.type = StringExpression, .string = t.string};
  case TokenType_Ident: {
    Token next = peekToken(it);
    if (next.type == TokenType_Star || next.type == TokenType_Plus ||
        next.type == TokenType_Hyphen || next.type == TokenType_Slash ||
        next.type == TokenType_Equal) {
      if (nextToken(it).type == TokenType_Equal) { // op
        if (peekToken(it).type != TokenType_Equal) {
          panic("Invalid expression following <num> =");
        }
        // ==
        //  ^
        nextToken(it);
      }
      Result(Slice_Expression) lr_res = alloc(ally, Expression, 2);
      if (!lr_res.ok)
        panic(lr_res.err);
      Expression *left = &lr_res.val.ptr[0];
      Expression *right = &lr_res.val.ptr[1];
      *left = (Expression){
          .type = IdentifierExpression,
          .number = t.ident,
      };
      *right = parseExpression(ally, it, nextToken(it));
      return (Expression){
          .type = ArithmeticExpression,
          .arithmetic =
              {
                  .op = next.type == TokenType_Star     ? '*'
                        : next.type == TokenType_Plus   ? '+'
                        : next.type == TokenType_Hyphen ? '-'
                        : next.type == TokenType_Equal  ? '=' // comparison
                                                        : '/',
                  .left = left,
                  .right = right,
              },
      };
    }
    if (next.type == TokenType_OpenParen) {
      // call expression
      nextToken(it);
      Result(Vec_Expression) res = createVec(ally, Expression, 1);
      if (!res.ok) {
        panic(res.err);
      }
      Vec(Expression) parameters = res.val;
      Token param = nextToken(it);
      while (param.type != TokenType_CloseParen) {
        if (param.type == TokenType_EOF) {
          panic("parseExpression: Unclosed open paren");
        }
        Expression expr = parseExpression(ally, it, param);
        Token paramSep = nextToken(it);
        if (paramSep.type != TokenType_Comma &&
            paramSep.type != TokenType_CloseParen) {
          panic("parseExpression: Parameter list expression not followed by "
                "comma or close paren ^");
        }
        if (!append(&parameters, Expression, &expr)) {
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
  case TokenType_OpenCurly:
  case TokenType_CloseCurly:
  case TokenType_Semi:
  case TokenType_Comma:
  case TokenType_Colon:
  case TokenType_Equal:
  case TokenType_Star:
  case TokenType_Plus:
  case TokenType_Hyphen:
  case TokenType_Slash:
  case TokenType_InlineBatch:
  case TokenType_Unknown: {
    printToken(t);
    panic("\nparseExpression: Invalid TokenType ^");
  }
  }
}

static Statement parseStatement(Allocator ally, TokenIterator *it) {
  TokenIterator snapshot = *it;
  Token t = nextToken(it);

  switch (t.type) {

  case TokenType_Ident:
  case TokenType_Number:
  case TokenType_String: {
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
      Token semi = nextToken(it);
      if (semi.type != TokenType_Semi) {
        printToken(semi);
        panic("\nparse: Unknown token following expression statement ^");
      }
      return decl_stmt;
    } else if (t.type == TokenType_Ident &&
               eql(t.ident, (Slice(char)){.ptr = "if", .len = 2})) {
      if (peekToken(it).type != TokenType_OpenParen) {
        panic("Missing ( after if");
      }
      nextToken(it); // (
      Expression condition = parseExpression(ally, it, nextToken(it));
      if (peekToken(it).type != TokenType_CloseParen) {
        printToken(peekToken(it));
        panic("\nMissing ) after if condition");
      }
      nextToken(it); // )
      Result(Slice_If) if_res = alloc(ally, If, 1);
      if (!if_res.ok)
        panic(if_res.err);
      If *if_statement = if_res.val.ptr;
      Result(Slice_Statement) cons_res = alloc(ally, Statement, 1);
      if (!cons_res.ok)
        panic(cons_res.err);
      Statement *consequence = cons_res.val.ptr;
      *consequence = parseStatement(ally, it);
      if_statement->condition = condition;
      if_statement->consequence = consequence;
      if_statement->alternate = NULL;
      Token elseToken = peekToken(it);
      if (elseToken.type == TokenType_Ident &&
          eql(elseToken.ident, (Slice(char)){.ptr = "else", .len = 4})) {
        nextToken(it);
        Result(Slice_Statement) alt_res = alloc(ally, Statement, 1);
        if (!alt_res.ok)
          panic(alt_res.err);
        Statement *alternate = alt_res.val.ptr;
        *alternate = parseStatement(ally, it);
        if_statement->alternate = alternate;
      }
      Statement s = {
          .type = IfStatement,
          .if_statement = if_statement,
      };
      return s;
    } else if (t.type == TokenType_Ident &&
               peekToken(it).type == TokenType_Equal) {
      nextToken(it);
      Expression value = parseExpression(ally, it, nextToken(it));

      Statement assign_stmt = {
          .type = AssignmentStatement,
          .assignment = {.name = t.ident, .value = value},
      };
      Token semi = nextToken(it);
      if (semi.type != TokenType_Semi) {
        printToken(semi);
        panic("\nparse: Unknown token following expression statement ^");
      }
      return assign_stmt;
    } else {
      Statement s = {
          .type = ExpressionStatement,
          .expression = parseExpression(ally, it, t),
      };
      Token semi = nextToken(it);
      if (semi.type != TokenType_Semi) {
        printToken(semi);
        panic("\nparse: Unknown token following expression statement ^");
      }
      return s;
    }
  } break;
  case TokenType_InlineBatch: {
    Statement s = {
        .type = InlineBatchStatement,
        .inline_batch = t.inline_batch,
    };
    return s;
  } break;
  case TokenType_OpenCurly: {
    Result(Vec_Statement) statements_res = createVec(ally, Statement, 4);
    if (!statements_res.ok)
      panic(statements_res.err);
    Vec(Statement) statements = statements_res.val;
    Statement stmt = parseStatement(ally, it);
    while (stmt.type) {
      printStatement(stmt);
      if (!append(&statements, Statement, &stmt)) {
        panic("Failed to append statement in block");
      }
      stmt = parseStatement(ally, it);
    }
    Token closecurly = peekToken(it);
    if (closecurly.type != TokenType_CloseCurly) {
      printToken(closecurly);
      printf("fart\n");
      panic("\nparse: Unknown token following block ^");
    }
    nextToken(it); // }
    Result(Slice_Block) block_res = alloc(ally, Block, 1);
    if (!block_res.ok)
      panic(block_res.err);
    block_res.val.ptr->statements = statements.slice;
    return (Statement){.type = BlockStatement, .block = block_res.val.ptr};
  } break;
  case TokenType_EOF:
  case TokenType_OpenParen:
  case TokenType_CloseParen:
  case TokenType_CloseCurly:
  case TokenType_Semi:
  case TokenType_Comma:
  case TokenType_Colon:
  case TokenType_Equal:
  case TokenType_Star:
  case TokenType_Plus:
  case TokenType_Hyphen:
  case TokenType_Slash:
  case TokenType_Unknown: {
    *it = snapshot; // restore
    return (Statement){.type = StatementEOF};
  } break;
  }
}

static Program parse(Allocator ally, TokenIterator *it) {
  Result(Vec_Statement) res = createVec(ally, Statement, 16);
  if (!res.ok) {
    panic("parse: Failed to alloc statements");
  }
  Vec(Statement) statements = res.val;

  Statement stmt = parseStatement(ally, it);
  while (stmt.type) {
    if (!append(&statements, Statement, &stmt)) {
      panic("Failed to append to statement list");
    }
    stmt = parseStatement(ally, it);
  }

  shrinkToLength(&statements, Statement);
  return (Program){.statements = statements.slice};
}

#endif /* PARSER_H */
