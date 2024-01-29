#include "../std/Vec.c"
#include "../std/eql.c"
#include "parser.c"
#include "sema.c"
#include <stdbool.h>
#include <stdio.h>

DefVec(char);
DefResult(Vec_char);

#ifdef BUILDING_WITH_ZIG
extern void emitExpression(Expression expr, StatementType parent,
                           Allocator ally, Vec(Statement) * temporaries,
                           Vec(char) * out, size_t *call_labels);
extern Slice(char) trim(Slice(char) str);
extern void emitStatement(Statement stmt, Allocator ally,
                          Vec(Statement) * temporaries, Vec(char) * out,
                          size_t *branch_labels, size_t *loop_labels,
                          size_t *call_labels, Vec(Binding) * names,
                          Vec(Statement) * outer_assignments,
                          Vec(char) * functions);
extern void outputBatch(Program prog, Allocator ally, Vec(char) * out);
#else
static void emitExpression(Expression expr, StatementType parent,
                           Allocator ally, Vec(Statement) * temporaries,
                           Vec(char) * out, size_t *call_labels) {
  switch (expr.type) {
  case IdentifierExpression: {
    if (parent == IfStatement || parent == WhileStatement) {
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
    Result(Vec_char) call_res = createVec(ally, char, 32);
    if (!call_res.ok)
      panic(call_res.err);
    Vec(char) call = call_res.val;
    appendManyCString(&call, "@call :");
    appendSlice(&call, char, expr.call.callee->identifier);
    for (size_t i = 0; i < expr.call.parameters_len; i++) {
      appendManyCString(&call, " ");
      Expression param = expr.call.parameters[i];
      emitExpression(param, parent, ally, temporaries, &call, call_labels);
    }
    appendManyCString(&call, "\r\n");
    Statement call_stmt = {
        .type = InlineBatchStatement,
        .inline_batch = call.slice,
    };
    if (!append(temporaries, Statement, &call_stmt)) {
      panic("Failed to append");
    }
    Result(Vec_char) ret_res = createVec(ally, char, 32);
    if (!ret_res.ok)
      panic(ret_res.err);
    Vec(char) ret = ret_res.val;
    size_t call_label = *call_labels;
    *call_labels += 1;
    ret.slice.len += (size_t)sprintf(ret.slice.ptr, "_ret%zu_", call_label);
    Statement ret_tmp = {
        .type = DeclarationStatement,
        .declaration =
            {
                .name = ret.slice,
                .value =
                    {
                        .type = IdentifierExpression,
                        .identifier = {.ptr = "__ret__", .len = 7},
                    },
                .constant = true,
            },
    };
    if (!append(temporaries, Statement, &ret_tmp)) {
      panic("Failed to append");
    }
    appendManyCString(out, "%");
    appendSlice(out, char, ret.slice);
    appendManyCString(out, "%");
  } break;
  case ArithmeticExpression: {
    if ((parent != DeclarationStatement && parent != AssignmentStatement &&
         expr.arithmetic.op != '=' && expr.arithmetic.op != '!') ||
        ((parent == DeclarationStatement || parent == AssignmentStatement) &&
         (expr.arithmetic.op == '=' || expr.arithmetic.op == '!'))) {
      // Create a temporary
      char temporary_string[128];
      int temporary_string_len =
          sprintf(temporary_string, "_tmp%zu_", temporaries->slice.len);
      Result(Slice_char) tmp_str =
          alloc(ally, char, (size_t)temporary_string_len);
      if (!tmp_str.ok)
        panic(tmp_str.err);
      for (int i = 0; i < temporary_string_len; i++) {
        tmp_str.val.ptr[i] = temporary_string[i];
      }
      Statement temporary;
      if (expr.arithmetic.op == '=' || expr.arithmetic.op == '!') {
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
          parent, ally, temporaries, out, call_labels);
    } else {
      char quot = '"';
      if (expr.arithmetic.op == '=' || expr.arithmetic.op == '!') {
        append(out, char, &quot);
      }
      emitExpression(*expr.arithmetic.left, DeclarationStatement, ally,
                     temporaries, out, call_labels);
      if (expr.arithmetic.op == '=') {
        appendManyCString(out, "\"==\"");
      } else if (expr.arithmetic.op == '!') {
        appendManyCString(out, "\" NEQ \"");
      } else if (expr.arithmetic.op == '%') {
        appendManyCString(out, "%%");
      } else {
        append(out, char, &expr.arithmetic.op);
      }
      emitExpression(*expr.arithmetic.right, DeclarationStatement, ally,
                     temporaries, out, call_labels);
      if (expr.arithmetic.op == '=' || expr.arithmetic.op == '!') {
        append(out, char, &quot);
      }
    }
  } break;
  case FunctionExpression: {
    panic("emitExpression with FunctionExpression: Should not be called");
  }
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
                          size_t *branch_labels, size_t *loop_labels,
                          size_t *call_labels, Vec(Binding) * names,
                          Vec(Statement) * outer_assignments,
                          Vec(char) * functions) {
  char equal = '=';
  switch (stmt.type) {
  case DeclarationStatement: {
    if (stmt.declaration.value.type == FunctionExpression) {
      appendManyCString(functions, ":");
      appendSlice(functions, char, stmt.declaration.name);
      appendManyCString(functions, "\r\n");
      char tmp_str[32];
      size_t tmp_str_len = 0;

      Result(Vec_Statement) body_contents_res = createVec(ally, Statement, 2);
      if (!body_contents_res.ok)
        panic(body_contents_res.err);
      Vec(Statement) body_contents = body_contents_res.val;

      for (size_t i = 0;
           i < stmt.declaration.value.function_expression.parameters_len; i++) {
        Expression param =
            stmt.declaration.value.function_expression.parameters[i];
        tmp_str_len = (size_t)sprintf(tmp_str, "@set %1.*s=%%~%zu\r\n",
                                      (int)param.identifier.len,
                                      param.identifier.ptr, i + 1);
        Result(Slice_char) str = alloc(ally, char, tmp_str_len);
        if (!str.ok)
          panic(str.err);
        for (size_t j = 0; j < tmp_str_len; j++) {
          str.val.ptr[j] = tmp_str[j];
        }
        Statement decl = {
            .type = InlineBatchStatement,
            .inline_batch = str.val,
        };
        append(&body_contents, Statement, &decl);
      }

      if (!appendSlice(&body_contents, Statement,
                       stmt.declaration.value.function_expression.body->block
                           ->statements)) {
        panic("Failed to copy body contents");
      }
      shrinkToLength(&body_contents, Statement);
      Block bodyBlockWithParams = {
          .statements = body_contents.slice,
      };
      Statement bodyWithParams = {
          .type = BlockStatement,
          .block = &bodyBlockWithParams,
      };
      emitStatement(bodyWithParams, ally, temporaries, functions, branch_labels,
                    loop_labels, call_labels, names, outer_assignments,
                    functions);
      break;
    }
    appendManyCString(out, "@set ");
    if (stmt.declaration.value.type == ArithmeticExpression &&
        stmt.declaration.value.arithmetic.op != '=') {
      appendManyCString(out, "/a ");
    }
    appendSlice(out, char, stmt.declaration.name);
    append(out, char, &equal);
    emitExpression(stmt.declaration.value, DeclarationStatement, ally,
                   temporaries, out, call_labels);
    Binding binding = {
        .name = stmt.declaration.name,
        .constant = stmt.declaration.constant,
        .read = false,
    };
    if (!append(names, Binding, &binding)) {
      panic("Could not append name");
    }
    appendManyCString(out, "\r\n");
  } break;
  case AssignmentStatement: {
    appendManyCString(out, "@set ");
    if (stmt.assignment.value.type == ArithmeticExpression) {
      appendManyCString(out, "/a ");
    }
    appendSlice(out, char, stmt.assignment.name);
    append(out, char, &equal);
    emitExpression(stmt.assignment.value, AssignmentStatement, ally,
                   temporaries, out, call_labels);
    bool name_exists = false;
    for (size_t i = 0; i < names->slice.len; i++) {
      if (eql(names->slice.ptr[i].name, stmt.assignment.name)) {
        name_exists = true;
      }
    }
    if (!name_exists && outer_assignments) {
      bool exists = false;
      for (size_t i = 0; i < outer_assignments->slice.len; i++) {
        Statement outer = outer_assignments->slice.ptr[i];
        if (eql(outer.assignment.name, stmt.assignment.name)) {
          exists = true;
        }
      }
      if (!exists) {
        Statement outer_stmt = {
            .type = AssignmentStatement,
            .assignment =
                {
                    .name = stmt.assignment.name,
                    .value =
                        {
                            .type = IdentifierExpression,
                            .identifier = stmt.assignment.name,
                        },
                },
        };
        if (!append(outer_assignments, Statement, &outer_stmt)) {
          panic("Failed to append outer assignment");
        }
      }
    }
    appendManyCString(out, "\r\n");
  } break;
  case InlineBatchStatement: {
    // appendManyCString(out, "\r\n");
    appendSlice(out, char, trim(stmt.inline_batch));
    appendManyCString(out, "\r\n");
  } break;
  case BlockStatement: {
    appendManyCString(out, "@setlocal EnableDelayedExpansion\r\n");
    Result(Vec_Statement) new_outer_assignments_res =
        createVec(ally, Statement, 1);
    if (!new_outer_assignments_res.ok)
      panic(new_outer_assignments_res.err);
    Vec(Statement) new_outer_assignments = new_outer_assignments_res.val;
    Result(Vec_Binding) block_names_res = createVec(ally, Binding, 8);
    if (!block_names_res.ok)
      panic(block_names_res.err);
    Vec(Binding) block_names = block_names_res.val;
    for (size_t i = 0; i < stmt.block->statements.len; i++) {
      emitStatement(stmt.block->statements.ptr[i], ally, temporaries, out,
                    branch_labels, loop_labels, call_labels, &block_names,
                    &new_outer_assignments, functions);
    }

    appendManyCString(out, "@endlocal");
    for (size_t i = 0; i < new_outer_assignments.slice.len; i++) {
      Statement assignment = new_outer_assignments.slice.ptr[i];
      appendManyCString(out, " && set \"");
      appendSlice(out, char, assignment.assignment.name);
      appendManyCString(out, "=%");
      appendSlice(out, char, assignment.assignment.value.identifier);
      appendManyCString(out, "%\"");
    }
    appendManyCString(out, "\r\n");
  } break;
  case IfStatement: {
    char temporary_string[128];
    size_t temporary_string_len = 0;
    Slice(char) branch_slice;
    size_t branch_label = *branch_labels;
    *branch_labels += 1;
    appendManyCString(out, "@if not ");
    emitExpression(stmt.if_statement->condition, IfStatement, ally, temporaries,
                   out, call_labels);

    appendManyCString(out, " goto :");
    temporary_string_len = (size_t)sprintf(
        temporary_string,
        stmt.if_statement->alternate ? "_else%zu_" : "_endif%zu_",
        branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
    emitStatement(*stmt.if_statement->consequence, ally, temporaries, out,
                  branch_labels, loop_labels, call_labels, names,
                  outer_assignments, functions);
    appendManyCString(out, "@goto :");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_endif%zu_", branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
    if (stmt.if_statement->alternate) {
      appendManyCString(out, ":");
      temporary_string_len =
          (size_t)sprintf(temporary_string, "_else%zu_", branch_label);
      branch_slice =
          (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
      appendSlice(out, char, branch_slice);
      appendManyCString(out, "\r\n");
      emitStatement(*stmt.if_statement->alternate, ally, temporaries, out,
                    branch_labels, loop_labels, call_labels, names,
                    outer_assignments, functions);
    }
    appendManyCString(out, ":");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_endif%zu_", branch_label);
    branch_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, branch_slice);
    appendManyCString(out, "\r\n");
  } break;
  case WhileStatement: {
    char temporary_string[128];
    size_t temporary_string_len = 0;
    Slice(char) loop_slice;
    size_t loop_label = *loop_labels;
    *loop_labels += 1;
    appendManyCString(out, ":");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_while%zu_", loop_label);
    loop_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, loop_slice);
    appendManyCString(out, "\r\n@if not ");
    emitExpression(stmt.while_statement->condition, WhileStatement, ally,
                   temporaries, out, call_labels);

    appendManyCString(out, " goto :");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_endwhile%zu_", loop_label);
    loop_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, loop_slice);
    appendManyCString(out, "\r\n");
    emitStatement(*stmt.while_statement->body, ally, temporaries, out,
                  branch_labels, loop_labels, call_labels, names,
                  outer_assignments, functions);
    appendManyCString(out, "@goto :");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_while%zu_", loop_label);
    loop_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, loop_slice);
    appendManyCString(out, "\r\n:");
    temporary_string_len =
        (size_t)sprintf(temporary_string, "_endwhile%zu_", loop_label);
    loop_slice =
        (Slice(char)){.ptr = temporary_string, .len = temporary_string_len};
    appendSlice(out, char, loop_slice);
    appendManyCString(out, "\r\n");
  } break;
  case ReturnStatement: {
    Result(Vec_Statement) ftemporaries_res = createVec(ally, Statement, 2);
    if (!ftemporaries_res.ok)
      panic(ftemporaries_res.err);
    Vec(Statement) ftemporaries = ftemporaries_res.val;
    Result(Vec_char) fbuffered_res = createVec(ally, char, 32);
    if (!fbuffered_res.ok)
      panic(fbuffered_res.err);
    Vec(char) fbuffered = fbuffered_res.val;
    appendManyCString(&fbuffered, "@endlocal");
    if (stmt.return_statement) {
      appendManyCString(&fbuffered, " && set \"__ret__=");
      emitExpression(*stmt.return_statement, ReturnStatement, ally,
                     &ftemporaries, &fbuffered, call_labels);
      for (size_t j = 0; j < ftemporaries.slice.len; j++) {
        emitStatement(ftemporaries.slice.ptr[j], ally, &ftemporaries, out,
                      branch_labels, loop_labels, call_labels, names, NULL,
                      &fbuffered);
      }

      appendManyCString(&fbuffered, "\"");
    }
    appendManyCString(&fbuffered, " && exit /b 0\r\n");
    shrinkToLength(&fbuffered, char);
    appendSlice(out, char, fbuffered.slice);
  } break;
  case ExpressionStatement: {
    Expression expr = stmt.expression;
    switch (expr.type) {
    case CallExpression: {
      if (expr.call.callee->type != IdentifierExpression) {
        fprintf(stdout, "Skipped unknown callee\n");
        break;
      }
      if (eql(expr.call.callee->identifier,
              (Slice(char)){.ptr = "print", .len = 5})) {

        appendManyCString(out, "@echo");
        for (size_t j = 0; j < expr.call.parameters_len; j++) {
          appendManyCString(out, " ");
          emitExpression(expr.call.parameters[j], ExpressionStatement, ally,
                         temporaries, out, call_labels);
        }
        appendManyCString(out, "\r\n");
      } else {
        Result(Vec_char) call_res = createVec(ally, char, 32);
        if (!call_res.ok)
          panic(call_res.err);
        Vec(char) call = call_res.val;
        appendManyCString(&call, "@call :");
        appendSlice(&call, char, expr.call.callee->identifier);
        for (size_t i = 0; i < expr.call.parameters_len; i++) {
          appendManyCString(&call, " ");
          Expression param = expr.call.parameters[i];
          emitExpression(param, ExpressionStatement, ally, temporaries, &call,
                         call_labels);
        }
        appendManyCString(&call, "\r\n");
        shrinkToLength(&call, char);
        appendSlice(out, char, call.slice);
      }
    } break;
    case IdentifierExpression:
    case NumericExpression:
    case ArithmeticExpression:
    case FunctionExpression:
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

// static inline void emitTemporaries(Allocator ally, Vec(Statement) *
// temporaries,
//                                    Vec(char) * out, size_t *branch_labels,
//                                    size_t *loop_labels, size_t *call_labels,
//                                    Vec(Binding) * names,
//                                    Vec(char) * functions) {
//   for (size_t i = 0; i < temporaries->slice.len; i++) {
//     Result(Vec_char) buffered = createVec(ally, char, 32);
//     if (!buffered.ok)
//       panic(buffered.err);
//     size_t before = temporaries->slice.len;
//     emitStatement(temporaries->slice.ptr[i], ally, temporaries,
//     &buffered.val,
//                   branch_labels, loop_labels, call_labels, names, NULL,
//                   functions);
//     if (before != temporaries->slice.len) {
//       Vec(Statement) next_temporaries = {
//           .slice =
//               {
//                   .ptr = temporaries->slice.ptr + before,
//                   .len = temporaries->slice.len - before,
//               },
//           .ally = ally,
//           .cap = temporaries->cap - before,
//       };
//       emitTemporaries(ally, &next_temporaries, out, branch_labels,
//       loop_labels,
//                       call_labels, names, functions);
//       temporaries->cap = next_temporaries.cap + before;
//     }
//     appendSlice(out, char, buffered.val.slice);
//   }
// }

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

  Result(Vec_char) functions_res = createVec(ally, char, 32);
  if (!functions_res.ok)
    panic(functions_res.err);

  Vec(char) functions = functions_res.val;

  size_t branch_labels = 0;
  size_t loop_labels = 0;
  size_t call_labels = 0;

  Result(Vec_Binding) names_res = createVec(ally, Binding, 8);
  if (!names_res.ok)
    panic(names_res.err);
  Vec(Binding) names = names_res.val;

  for (size_t i = 0; i < prog.statements.len; i++) {
    Statement stmt = prog.statements.ptr[i];
    emitStatement(stmt, ally, &temporaries.val, &buffered.val, &branch_labels,
                  &loop_labels, &call_labels, &names, NULL, &functions);
    // emitTemporaries(ally, &temporaries.val, out, &branch_labels,
    // &loop_labels,
    //                 &call_labels, &names, &functions);
    for (size_t j = 0; j < temporaries.val.slice.len; j++) {
      emitStatement(temporaries.val.slice.ptr[j], ally, &temporaries.val, out,
                    &branch_labels, &loop_labels, &call_labels, &names, NULL,
                    &functions);
    }
    temporaries.val.slice.len = 0;
    appendSlice(out, char, buffered.val.slice);
    buffered.val.slice.len = 0;
  }

  appendManyCString(out, "\r\n@popd\r\n");
  appendManyCString(out, "@endlocal\r\n");
  appendManyCString(out, "@exit /b 0\r\n\r\n");

  appendSlice(out, char, functions.slice);

  Slice(Statement) allocation = {.ptr = temporaries.val.slice.ptr,
                                 .len = temporaries.val.cap};
  resizeAllocation(ally, Statement, &allocation, 0);
}

#endif
