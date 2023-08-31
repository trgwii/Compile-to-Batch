#include "../std/Allocator.c"
#include "../std/eql.c"
#include "parser.c"
#include <stdbool.h>

typedef struct {
  Slice(char) name;
  bool read;
  bool constant;
} Binding;

DefSlice(Binding);
DefVec(Binding);
DefResult(Vec_Binding);

static bool nameListHasString(Slice(Binding) list, Slice(char) string) {
  for (size_t i = 0; i < list.len; i++) {
    if (eql(list.ptr[i].name, string))
      return true;
  }
  return false;
}

static void analyzeExpression(Slice(Binding) names, Expression expr) {
  switch (expr.type) {
  case IdentifierExpression: {
    if (!nameListHasString(names, expr.identifier)) {
      if (!eql(expr.identifier, (Slice_char){.ptr = "print", .len = 5})) {
        fprintf(stdout, "Referring to undeclared name: %1.*s\n",
                (int)expr.identifier.len, expr.identifier.ptr);
      }
    } else {
      for (size_t i = 0; i < names.len; i++) {
        if (eql(names.ptr[i].name, expr.identifier)) {
          names.ptr[i].read = true;
        }
      }
    }
  } break;
  case CallExpression: {
    analyzeExpression(names, *expr.call.callee);
    for (size_t i = 0; i < expr.call.parameters_len; i++) {
      analyzeExpression(names, expr.call.parameters[i]);
    }
  } break;
  case ArithmeticExpression: {
    analyzeExpression(names, *expr.arithmetic.left);
    analyzeExpression(names, *expr.arithmetic.right);
  } break;
  case NumericExpression:
  case StringExpression: {
    // no-op
  }
  }
}

static void analyzeStatement(Vec(Binding) names, Statement stmt) {
  switch (stmt.type) {
  case DeclarationStatement: {
    if (nameListHasString(names.slice, stmt.declaration.name)) {
      fprintf(stdout, "Double declaration of: %1.*s\n",
              (int)stmt.declaration.name.len, stmt.declaration.name.ptr);
      return;
    }
    analyzeExpression(names.slice, stmt.declaration.value);
    Binding binding = {.name = stmt.declaration.name,
                       .constant = stmt.declaration.constant,
                       .read = false};
    if (!append(&names, Binding, &binding)) {
      panic("analyze: Failed to append to names");
    }
  } break;
  case AssignmentStatement: {
    if (!nameListHasString(names.slice, stmt.assignment.name)) {
      fprintf(stdout, "Assignment to undeclared name: %1.*s\n",
              (int)stmt.assignment.name.len, stmt.assignment.name.ptr);
    } else {
      for (size_t j = 0; j < names.slice.len; j++) {
        if (eql(names.slice.ptr[j].name, stmt.assignment.name)) {
          if (names.slice.ptr[j].constant) {
            fprintf(stdout, "Assignment to constant: %1.*s\n",
                    (int)stmt.assignment.name.len, stmt.assignment.name.ptr);
          }
        }
      }
    }
    analyzeExpression(names.slice, stmt.assignment.value);
  } break;
  case ExpressionStatement: {
    analyzeExpression(names.slice, stmt.expression);
  } break;
  case IfStatement: {
    analyzeExpression(names.slice, stmt.if_statement->condition);
    analyzeStatement(names, *stmt.if_statement->consequence);
    if (stmt.if_statement->alternate) {
      analyzeStatement(names, *stmt.if_statement->alternate);
    }
  } break;
  case BlockStatement: {
    for (size_t i = 0; i < stmt.block->statements.len; i++) {
      analyzeStatement(names, stmt.block->statements.ptr[i]);
    }
  } break;
  case InlineBatchStatement: {
  } break;
  case StatementEOF: {
    panic("StatementEOF");
  } break;
  }
}

static void analyze(Allocator ally, Program prog) {
  Result(Vec_Binding) names_res = createVec(ally, Binding, 4);
  if (!names_res.ok)
    panic(names_res.err);
  Vec(Binding) names = names_res.val;
  for (size_t i = 0; i < prog.statements.len; i++) {
    Statement stmt = prog.statements.ptr[i];
    analyzeStatement(names, stmt);
  }
  for (size_t i = 0; i < names.slice.len; i++) {
    Binding b = names.slice.ptr[i];
    if (!b.read) {
      fprintf(stdout, "Unused %s: %1.*s\n",
              b.constant ? "constant" : "variable", (int)b.name.len,
              b.name.ptr);
    }
  }
}
