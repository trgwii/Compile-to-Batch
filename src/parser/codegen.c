#include "../std/Vec.c"
#include "../std/eql.c"
#include "parser.c"
#include <stdbool.h>
#include <stdio.h>

DefVec(char);
DefResult(Vec_char);

static void emitExpression(Expression expr, StatementType parent,
                           Vec(Statement) * temporaries, Vec(char) * out) {
  switch (expr.type) {
  case IdentifierExpression: {
    char perc = '%';
    append(out, char, &perc);
    appendSlice(out, char, expr.identifier);
    append(out, char, &perc);
  } break;
  case NumericExpression: {
    appendSlice(out, char, expr.number);
  } break;
  case StringExpression: {
    for (size_t i = 0; i < expr.string.len; i++) {
      char c = expr.string.ptr[i];
      char caret = '^';
      if (c == '\\')
        append(out, char, &caret);
      else
        append(out, char, &c);
    }
  } break;
  case CallExpression: {
    fprintf(stdout, "Skipped emitting expression\n");
  } break;
  case ArithmeticExpression: {
    if (parent != DeclarationStatement && parent != AssignmentStatement) {
      Statement temporary = {
          .type = DeclarationStatement,
          .declaration = {.name = {.ptr = "_tmp_", .len = 5}, .value = expr},
      };
      append(temporaries, Statement, &temporary);
      emitExpression((Expression){.type = IdentifierExpression,
                                  .identifier = {.ptr = "_tmp_", .len = 5}},
                     parent, temporaries, out);
    } else {
      emitExpression(*expr.arithmetic.left, parent, temporaries, out);
      append(out, char, &expr.arithmetic.op);
      emitExpression(*expr.arithmetic.right, parent, temporaries, out);
    }
  } break;
  }
}

static void emitStatement(Statement stmt, Vec(Statement) * temporaries,
                          Vec(char) * out) {
  char quot = '"';
  char equal = '=';
  switch (stmt.type) {
  case DeclarationStatement: {
    appendManyCString(out, "@set ");
    if (stmt.declaration.value.type == ArithmeticExpression) {
      appendManyCString(out, "/a ");
    }
    append(out, char, &quot);
    appendSlice(out, char, stmt.declaration.name);
    append(out, char, &equal);
    emitExpression(stmt.declaration.value, DeclarationStatement, temporaries,
                   out);
    appendManyCString(out, "\"\r\n");
  } break;
  case AssignmentStatement: {
    appendManyCString(out, "@set ");
    if (stmt.assignment.value.type == ArithmeticExpression) {
      appendManyCString(out, "/a ");
    }
    append(out, char, &quot);
    appendSlice(out, char, stmt.assignment.name);
    append(out, char, &equal);
    emitExpression(stmt.assignment.value, AssignmentStatement, temporaries,
                   out);
    appendManyCString(out, "\"\r\n");
  } break;
  case ExpressionStatement: {
    Expression expr = stmt.expression;
    switch (expr.type) {
    case CallExpression: {
      if (expr.call.callee->type != IdentifierExpression) {
        fprintf(stdout, "Skipped unknown callee\n");
        break;
      }
      if (!eql(expr.call.callee->identifier,
               (Slice(char)){.ptr = "print", .len = 5})) {
        fprintf(stdout, "unknown function: ");
        fprintf(stdout, "%1.*s", (int)expr.call.callee->identifier.len,
                expr.call.callee->identifier.ptr);
        fprintf(stdout, "\n");
      }
      appendManyCString(out, "@echo");
      for (size_t j = 0; j < expr.call.parameters_len; j++) {
        appendManyCString(out, " ");
        emitExpression(expr.call.parameters[j], ExpressionStatement,
                       temporaries, out);
      }
      appendManyCString(out, "\r\n");
    } break;
    case IdentifierExpression:
    case NumericExpression:
    case ArithmeticExpression:
    case StringExpression: {
      fprintf(stdout, "Skipped unknown expression: ");
      fprintf(stdout, "%1.*s", (int)expr.string.len, expr.string.ptr);
      fprintf(stdout, "\n");
    } break;
    }
  } break;
  }
}

static void outputBatch(Program prog, Allocator ally, Vec(char) * out) {
  (void)ally;
  appendManyCString(out, "@setlocal EnableDelayedExpansion\r\n");
  appendManyCString(out, "@pushd \"%~dp0\"\r\n\r\n");

  Result(Vec_Statement) temporaries = createVec(ally, Statement, 2);
  if (!temporaries.ok)
    panic(temporaries.err);

  Result(Vec_char) buffered = createVec(ally, char, 64);
  if (!buffered.ok)
    panic(buffered.err);

  for (size_t i = 0; i < prog.statements.len; i++) {
    Statement stmt = prog.statements.ptr[i];
    emitStatement(stmt, &temporaries.val, &buffered.val);
    // TODO: clear and print temporaries
    for (size_t j = 0; j < temporaries.val.slice.len; j++) {
      emitStatement(temporaries.val.slice.ptr[j], NULL, out);
    }
    appendSlice(out, char, buffered.val.slice);
    buffered.val.slice.len = 0;
  }

  Slice(Statement) allocation = {.ptr = temporaries.val.slice.ptr,
                                 .len = temporaries.val.cap};
  resizeAllocation(ally, Statement, &allocation, 0);

  appendManyCString(out, "\r\n@popd\r\n");
  appendManyCString(out, "@endlocal\r\n");
}
