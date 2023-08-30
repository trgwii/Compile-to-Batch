#include "../std/eql.c"
#include "parser.c"
#include <stdbool.h>
#include <stdio.h>

static void emitExpression(Expression expr, FILE *out) {
  switch (expr.type) {
  case IdentifierExpression: {
    fprintf(out, "%%");
    fprintf(out, "%1.*s", (int)expr.identifier.len, expr.identifier.ptr);
    fprintf(out, "%%");
  } break;
  case NumericExpression: {
    fprintf(out, "%1.*s", (int)expr.number.len, expr.number.ptr);
  } break;
  case StringExpression: {
    for (size_t i = 0; i < expr.string.len; i++) {
      char c = expr.string.ptr[i];
      if (c == '\\')
        fprintf(out, "%c", '^');
      else
        fprintf(out, "%c", c);
    }
  } break;
  case CallExpression: {
    fprintf(stdout, "Skipped emitting expression\n");
  } break;
  case ArithmeticExpression: {
    emitExpression(*expr.arithmetic.left, out);
    fprintf(out, "%c", expr.arithmetic.op);
    emitExpression(*expr.arithmetic.right, out);
  } break;
  }
}

static void outputBatch(Program prog, FILE *out) {
  fprintf(out, "@setlocal EnableDelayedExpansion\r\n");
  fprintf(out, "@pushd \"%%~dp0\"\r\n\r\n");

  for (size_t i = 0; i < prog.statements.len; i++) {
    Statement stmt = prog.statements.ptr[i];
    switch (stmt.type) {
    case DeclarationStatement: {
      char *attributes =
          stmt.declaration.value.type == ArithmeticExpression ? "/a" : "";
      fprintf(out, "@set %s \"%1.*s=", attributes,
              (int)stmt.declaration.name.len, stmt.declaration.name.ptr);
      emitExpression(stmt.declaration.value, out);
      fprintf(out, "\"\r\n");
    } break;
    case AssignmentStatement: {
      char *attributes =
          stmt.assignment.value.type == ArithmeticExpression ? "/a" : "";
      fprintf(out, "@set %s \"%1.*s=", attributes,
              (int)stmt.assignment.name.len, stmt.assignment.name.ptr);
      emitExpression(stmt.assignment.value, out);
      fprintf(out, "\"\r\n");
    } break;
    case ExpressionStatement: {
      Expression expr = stmt.expression;
      switch (expr.type) {
      case CallExpression: {
        if (expr.call.callee->type != IdentifierExpression) {
          fprintf(stdout, "Skipped unknown callee\n");
          continue;
        }
        if (!eql(expr.call.callee->identifier,
                 (Slice(char)){.ptr = "print", .len = 5})) {
          fprintf(stdout, "unknown function: ");
          fprintf(stdout, "%1.*s", (int)expr.call.callee->identifier.len,
                  expr.call.callee->identifier.ptr);
          fprintf(stdout, "\n");
        }
        fprintf(out, "@echo");
        for (size_t j = 0; j < expr.call.parameters_len; j++) {
          fprintf(out, " ");
          emitExpression(expr.call.parameters[j], out);
        }
        fprintf(out, "\r\n");
      } break;
      case IdentifierExpression:
      case NumericExpression:
      case ArithmeticExpression:
      case StringExpression: {
        fprintf(stdout, "Skipped unknown expression: ");
        fprintf(stdout, "%1.*s", (int)expr.string.len, expr.string.ptr);
        fprintf(stdout, "\n");
        continue;
      } break;
      }
    } break;
    }
  }

  fprintf(out, "\r\n@popd\r\n");
  fprintf(out, "@endlocal\r\n");
}
