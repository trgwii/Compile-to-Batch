#include "../std/Allocator.c"
#include "../std/eql.c"
#include "parser.c"
#include <stdbool.h>

static bool listHasString(Slice(Slice_char) list, Slice(char) string) {
  for (size_t i = 0; i < list.len; i++) {
    if (eql(list.ptr[i], string))
      return true;
  }
  return false;
}

static void analyzeExpression(Slice(Slice_char) names, Expression expr) {
  switch (expr.type) {
  case IdentifierExpression: {
    if (!listHasString(names, expr.identifier)) {
      if (!eql(expr.identifier, (Slice_char){.ptr = "print", .len = 5})) {
        fprintf(stdout, "Referring to undeclared name: %1.*s\n",
                (int)expr.identifier.len, expr.identifier.ptr);
      }
    }
  } break;
  case CallExpression: {
    analyzeExpression(names, *expr.call.callee);
    for (size_t i = 0; i < expr.call.parameters_len; i++) {
      analyzeExpression(names, expr.call.parameters[i]);
    }
  } break;
  case NumericExpression:
  case StringExpression: {
  }
  }
}

static void analyze(Allocator ally, Program prog) {
  Result(Vec_Slice_char) names_res = createVec(ally, Slice_char, 16);
  if (!names_res.ok)
    panic(names_res.err);
  Vec(Slice_char) names = names_res.val;
  for (size_t i = 0; i < prog.statements.len; i++) {
    Statement stmt = prog.statements.ptr[i];
    switch (stmt.type) {
    case DeclarationStatement: {
      if (listHasString(names.slice, stmt.declaration.name)) {
        fprintf(stdout, "Double declaration of: %1.*s\n",
                (int)stmt.declaration.name.len, stmt.declaration.name.ptr);
      }
      if (!appendToVec(&names, Slice_char, &stmt.declaration.name)) {
        panic("analyze: Failed to append to names");
      }
      // TODO: check that assignments don't assign to constants
    } break;
    case ExpressionStatement: {
      analyzeExpression(names.slice, stmt.expression);
    } break;
    }
  }
}
