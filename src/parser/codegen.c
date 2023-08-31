#include "../std/Vec.c"
#include "../std/eql.c"
#include "parser.c"
#include <stdbool.h>
#include <stdio.h>

DefVec(char);
DefResult(Vec_char);

static void emitExpression(Expression expr, StatementType parent,
                           Allocator ally, Vec(Statement) * temporaries,
                           Vec(char) * out) {
  switch (expr.type) {
  case IdentifierExpression: {
    if (parent == IfStatement) {
      appendManyCString(out, "\"%");
      appendSlice(out, char, expr.identifier);
      appendManyCString(out, "%\"==\"true\"");
    } else {
      char perc = '%';
      append(out, char, &perc);
      appendSlice(out, char, expr.identifier);
      append(out, char, &perc);
    }
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
    char quot = '"';
    if ((parent != DeclarationStatement && parent != AssignmentStatement &&
         expr.arithmetic.op != '=') ||
        ((parent == DeclarationStatement || parent == AssignmentStatement) &&
         expr.arithmetic.op == '=')) {
      // Create a temporary
      char temporary_string[128];
      int temporary_string_len =
          sprintf(temporary_string, "_tmp%lu_", temporaries->slice.len);
      Result(Slice_char) tmp_str =
          alloc(ally, char, (size_t)temporary_string_len);
      if (!tmp_str.ok)
        panic(tmp_str.err);
      for (int i = 0; i < temporary_string_len; i++) {
        tmp_str.val.ptr[i] = temporary_string[i];
      }
      Statement temporary;
      if (expr.arithmetic.op == '=') {
        Result(Slice_If) if_res = alloc(ally, If, 1);
        if (!if_res.ok)
          panic(if_res.err);
        if_res.val.ptr->condition = expr;
        Result(Slice_Statement) con_res = alloc(ally, Statement, 1);
        if (!con_res.ok)
          panic(con_res.err);
        con_res.val.ptr->type = DeclarationStatement;
        con_res.val.ptr->declaration = (Declaration){
            .name = tmp_str.val,
            .value = {.type = StringExpression,
                      .string = {.ptr = "true", .len = 4}},
            .constant = true,
        };
        if_res.val.ptr->consequence = con_res.val.ptr;
        Result(Slice_Statement) alt_res = alloc(ally, Statement, 1);
        if (!alt_res.ok)
          panic(alt_res.err);
        alt_res.val.ptr->type = DeclarationStatement;
        alt_res.val.ptr->declaration = (Declaration){
            .name = tmp_str.val,
            .value = {.type = StringExpression,
                      .string = {.ptr = "false", .len = 5}},
            .constant = true,
        };
        if_res.val.ptr->alternate = alt_res.val.ptr;
        temporary =
            (Statement){.type = IfStatement, .if_statement = if_res.val.ptr};
      } else {
        temporary = (Statement){
            .type = DeclarationStatement,
            .declaration = {.name = tmp_str.val, .value = expr},
        };
      }
      append(temporaries, Statement, &temporary);
      emitExpression(
          (Expression){.type = IdentifierExpression, .identifier = tmp_str.val},
          parent, ally, temporaries, out);
    } else {
      append(out, char, &quot);
      emitExpression(*expr.arithmetic.left, BlockStatement, ally, temporaries,
                     out);
      if (expr.arithmetic.op == '=') {
        appendManyCString(out, "\"==\"");
      } else {
        append(out, char, &expr.arithmetic.op);
      }
      emitExpression(*expr.arithmetic.right, BlockStatement, ally, temporaries,
                     out);
      append(out, char, &quot);
    }
  } break;
  }
}

static Slice(char) trim(Slice(char) str) {
  while (isblank(str.ptr[0]) || isspace(str.ptr[0])) {
    str.ptr++;
    str.len--;
  }
  while (isblank(str.ptr[str.len - 1]) || isspace(str.ptr[str.len - 1])) {
    str.len--;
  }
  return str;
}

static void emitStatement(Statement stmt, Allocator ally,
                          Vec(Statement) * temporaries, Vec(char) * out,
                          size_t *branch_labels) {
  char quot = '"';
  char equal = '=';
  switch (stmt.type) {
  case DeclarationStatement: {
    appendManyCString(out, "@set ");
    if (stmt.declaration.value.type == ArithmeticExpression &&
        stmt.declaration.value.arithmetic.op != '=') {
      appendManyCString(out, "/a ");
    }
    append(out, char, &quot);
    appendSlice(out, char, stmt.declaration.name);
    append(out, char, &equal);
    emitExpression(stmt.declaration.value, DeclarationStatement, ally,
                   temporaries, out);
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
    emitExpression(stmt.assignment.value, AssignmentStatement, ally,
                   temporaries, out);
    appendManyCString(out, "\"\r\n");
  } break;
  case InlineBatchStatement: {
    // appendManyCString(out, "\r\n");
    appendSlice(out, char, trim(stmt.inline_batch));
    appendManyCString(out, "\r\n");
  } break;
  case BlockStatement: {
    appendManyCString(out, "@setlocal EnableDelayedExpansion\r\n");
    for (size_t i = 0; i < stmt.block->statements.len; i++) {
      emitStatement(stmt.block->statements.ptr[i], ally, temporaries, out,
                    branch_labels);
    }
    appendManyCString(out, "@endlocal\r\n");
  } break;
  case IfStatement: {
    char temporary_string[128];
    size_t temporary_string_len = 0;
    Slice(char) branch_slice;
    size_t branch_label = *branch_labels;
    *branch_labels += 1;
    appendManyCString(out, "@if not ");
    emitExpression(stmt.if_statement->condition, IfStatement, ally, temporaries,
                   out);

    appendManyCString(out, " goto :");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_else%lu_", branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
    emitStatement(*stmt.if_statement->consequence, ally, temporaries, out,
                  branch_labels);
    appendManyCString(out, "@goto :");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_done%lu_", branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
    appendManyCString(out, ":");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_else%lu_", branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
    if (stmt.if_statement->alternate) {
      emitStatement(*stmt.if_statement->alternate, ally, temporaries, out,
                    branch_labels);
    }
    appendManyCString(out, ":");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_done%lu_", branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
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
        emitExpression(expr.call.parameters[j], ExpressionStatement, ally,
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
  case StatementEOF: {
    panic("StatementEOF");
  } break;
  }
}

static void outputBatch(Program prog, Allocator ally, Vec(char) * out) {
  (void)ally;
  appendManyCString(out, "@setlocal EnableDelayedExpansion\r\n");
  appendManyCString(out, "@pushd \"%~dp0\"\r\n\r\n");

  Result(Vec_Statement) temporaries = createVec(ally, Statement, 1);
  if (!temporaries.ok)
    panic(temporaries.err);

  Result(Vec_char) buffered = createVec(ally, char, 32);
  if (!buffered.ok)
    panic(buffered.err);

  size_t branch_labels = 0;

  for (size_t i = 0; i < prog.statements.len; i++) {
    Statement stmt = prog.statements.ptr[i];
    emitStatement(stmt, ally, &temporaries.val, &buffered.val, &branch_labels);
    for (size_t j = 0; j < temporaries.val.slice.len; j++) {
      emitStatement(temporaries.val.slice.ptr[j], ally, &temporaries.val, out,
                    &branch_labels);
    }
    temporaries.val.slice.len = 0;
    appendSlice(out, char, buffered.val.slice);
    buffered.val.slice.len = 0;
  }

  Slice(Statement) allocation = {.ptr = temporaries.val.slice.ptr,
                                 .len = temporaries.val.cap};
  resizeAllocation(ally, Statement, &allocation, 0);

  appendManyCString(out, "\r\n@popd\r\n");
  appendManyCString(out, "@endlocal\r\n");
}
