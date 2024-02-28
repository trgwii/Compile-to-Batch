const std = @import("std");
const p = @import("parser.zig");
const s = @import("sema.zig");
const a = @import("../std/Allocator.zig");
const Slice = @import("../std/Slice.zig").Slice;
const v = @import("../std/Vec.zig");

pub export fn emitExpression(
    expr: p.Expression,
    parent: p.StatementType,
    ally: a.Allocator,
    temporaries: *v.Vec(p.Statement),
    out: *v.Vec(u8),
    call_labels: *usize,
) void {
    switch (expr.tag) {
        .identifier => {
            if (parent == .@"if" or parent == .@"while") {
                _ = v.appendManyCString(out, "\"%");
                _ = v.appendSlice(u8, out, expr.x.identifier);
                _ = v.appendManyCString(out, "%\"==\"true\"");
            } else {
                const perc: u8 = '%';
                _ = v.append(u8, out, &perc);
                _ = v.appendSlice(u8, out, expr.x.identifier);
                _ = v.append(u8, out, &perc);
            }
        },
        .numeric => {
            _ = v.appendSlice(u8, out, expr.x.number);
        },
        .string => {
            for (expr.x.string.toZig()) |c| {
                _ = v.append(u8, out, if (c == '\\') &'^' else &c);
            }
        },
        .call => {
            const call_res = v.createVec(u8, ally, 32);
            if (!call_res.ok) @panic(std.mem.span(call_res.x.err));
            var call = call_res.x.val;
            _ = v.appendManyCString(&call, "@call :");
            _ = v.appendSlice(u8, &call, expr.x.call.callee.x.identifier);
            for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param| {
                _ = v.appendManyCString(&call, " ");
                emitExpression(param, parent, ally, temporaries, &call, call_labels);
            }
            _ = v.appendManyCString(&call, "\r\n");
            const call_stmt = p.Statement{
                .tag = .inline_batch,
                .x = .{ .inline_batch = call.slice },
            };
            if (!v.append(p.Statement, temporaries, &call_stmt)) @panic("Failed to append");
            const ret_res = v.createVec(u8, ally, 32);
            if (!ret_res.ok) @panic(std.mem.span(ret_res.x.err));
            var ret = ret_res.x.val;
            const call_label = call_labels.*;
            call_labels.* += 1;
            ret.slice.len += (std.fmt.bufPrint(
                ret.slice.ptr[0..ret.cap],
                "_ret{}_",
                .{call_label},
            ) catch unreachable).len;
            const ret_tmp = p.Statement{
                .tag = .declaration,
                .x = .{ .declaration = .{
                    .name = ret.slice,
                    .value = .{
                        .tag = .identifier,
                        .x = .{ .identifier = .{ .ptr = @constCast("__ret__"), .len = 7 } },
                    },
                    .constant = true,
                } },
            };
            if (!v.append(p.Statement, temporaries, &ret_tmp)) @panic("Failed to append");
            _ = v.appendManyCString(out, "%");
            _ = v.appendSlice(u8, out, ret.slice);
            _ = v.appendManyCString(out, "%");
        },
        .arithmetic => {
            if ((parent != .declaration and parent != .assignment and expr.x.arithmetic.op != '=' and expr.x.arithmetic.op != '!') or
                ((parent == .declaration or parent == .assignment) and
                (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!')))
            {
                var temporary_string: [128]u8 = undefined;
                const temporary_string_len = (std.fmt.bufPrint(
                    &temporary_string,
                    "_tmp{}_",
                    .{temporaries.slice.len},
                ) catch unreachable).len;
                const tmp_str = a.alloc(ally, u8, temporary_string_len);
                if (!tmp_str.ok) @panic(std.mem.span(tmp_str.x.err));
                for (tmp_str.x.val.toZig(), temporary_string[0..temporary_string_len]) |*dst, *src| {
                    dst.* = src.*;
                }
                var temporary: p.Statement = undefined;
                if (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!') {
                    const if_res = a.alloc(ally, p.If, 1);
                    if (!if_res.ok) @panic(std.mem.span(if_res.x.err));
                    if_res.x.val.ptr[0].condition = expr;
                    const con_res = a.alloc(ally, p.Statement, 1);
                    if (!con_res.ok) @panic(std.mem.span(con_res.x.err));
                    con_res.x.val.ptr[0].tag = .declaration;
                    con_res.x.val.ptr[0].x.declaration = .{
                        .name = tmp_str.x.val,
                        .value = .{
                            .tag = .string,
                            .x = .{ .string = .{ .ptr = @constCast("true"), .len = 4 } },
                        },
                        .constant = true,
                    };
                    if_res.x.val.ptr[0].consequence = &con_res.x.val.ptr[0];
                    const alt_res = a.alloc(ally, p.Statement, 1);
                    if (!alt_res.ok) @panic(std.mem.span(alt_res.x.err));
                    alt_res.x.val.ptr[0].tag = .declaration;
                    alt_res.x.val.ptr[0].x.declaration = .{
                        .name = tmp_str.x.val,
                        .value = .{
                            .tag = .string,
                            .x = .{ .string = .{ .ptr = @constCast("false"), .len = 5 } },
                        },
                        .constant = true,
                    };
                    if_res.x.val.ptr[0].alternate = &alt_res.x.val.ptr[0];
                    temporary = .{ .tag = .@"if", .x = .{ .@"if" = &if_res.x.val.ptr[0] } };
                } else {
                    temporary = .{
                        .tag = .declaration,
                        .x = .{ .declaration = .{
                            .name = tmp_str.x.val,
                            .value = expr,
                            .constant = true,
                        } },
                    };
                }
                _ = v.append(p.Statement, temporaries, &temporary);
                emitExpression(
                    .{ .tag = .identifier, .x = .{ .identifier = tmp_str.x.val } },
                    parent,
                    ally,
                    temporaries,
                    out,
                    call_labels,
                );
            } else {
                const quot: u8 = '"';
                if (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!') {
                    _ = v.append(u8, out, &quot);
                }
                emitExpression(expr.x.arithmetic.left.*, .declaration, ally, temporaries, out, call_labels);
                if (expr.x.arithmetic.op == '=') {
                    _ = v.appendManyCString(out, "\"==\"");
                } else if (expr.x.arithmetic.op == '!') {
                    _ = v.appendManyCString(out, "\" NEQ \"");
                } else if (expr.x.arithmetic.op == '%') {
                    _ = v.appendManyCString(out, "%%");
                } else {
                    _ = v.append(u8, out, &expr.x.arithmetic.op);
                }
                emitExpression(expr.x.arithmetic.right.*, .declaration, ally, temporaries, out, call_labels);
                if (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!') {
                    _ = v.append(u8, out, &quot);
                }
            }
        },
        .function => {
            @panic("emitExpression with FunctionExpression: Should not be called");
        },
    }
}

pub export fn trim(str: Slice(u8)) Slice(u8) {
    const res = std.mem.trim(u8, str.toZig(), &std.ascii.whitespace);
    return .{ .ptr = @constCast(res.ptr), .len = res.len };
}

pub export fn emitStatement(
    stmt: p.Statement,
    ally: a.Allocator,
    temporaries: *v.Vec(p.Statement),
    out: *v.Vec(u8),
    branch_labels: *usize,
    loop_labels: *usize,
    call_labels: *usize,
    names: *v.Vec(s.Binding),
    outer_assignments: ?*v.Vec(p.Statement),
    functions: *v.Vec(u8),
) void {
    const stdout = std.io.getStdOut().writer();
    const equal: u8 = '=';
    switch (stmt.tag) {
        .declaration => b: {
            if (stmt.x.declaration.value.tag == .function) {
                _ = v.appendManyCString(functions, ":");
                _ = v.appendSlice(u8, functions, stmt.x.declaration.name);
                _ = v.appendManyCString(functions, "\r\n");
                var tmp_str: [32]u8 = undefined;
                var tmp_str_len: usize = 0;
                const body_contents_res = v.createVec(p.Statement, ally, 2);
                if (!body_contents_res.ok) @panic(std.mem.span(body_contents_res.x.err));
                var body_contents = body_contents_res.x.val;
                for (stmt.x.declaration.value.x.function_expression.parameters[0..stmt.x.declaration.value.x.function_expression.parameters_len], 0..) |param, i| {
                    tmp_str_len = (std.fmt.bufPrint(
                        &tmp_str,
                        "@set {s}=%~{}\r\n",
                        .{ param.x.identifier.toZig(), i + 1 },
                    ) catch unreachable).len;
                    const str = a.alloc(ally, u8, tmp_str_len);
                    if (!str.ok) @panic(std.mem.span(str.x.err));
                    for (tmp_str[0..tmp_str_len], 0..) |c, j| {
                        str.x.val.ptr[j] = c;
                    }
                    const decl = p.Statement{
                        .tag = .inline_batch,
                        .x = .{ .inline_batch = str.x.val },
                    };
                    _ = v.append(p.Statement, &body_contents, &decl);
                }
                if (!v.appendSlice(p.Statement, &body_contents, stmt.x.declaration.value.x.function_expression.body.x.block.statements)) {
                    @panic("Failed to copy body contents");
                }
                v.shrinkToLength(p.Statement, &body_contents);
                var bodyBlockWithParams = p.Block{
                    .statements = body_contents.slice,
                };
                const bodyWithParams = p.Statement{
                    .tag = .block,
                    .x = .{ .block = &bodyBlockWithParams },
                };
                emitStatement(
                    bodyWithParams,
                    ally,
                    temporaries,
                    functions,
                    branch_labels,
                    loop_labels,
                    call_labels,
                    names,
                    outer_assignments,
                    functions,
                );
                break :b;
            }
            _ = v.appendManyCString(out, "@set ");
            if (stmt.x.declaration.value.tag == .arithmetic and stmt.x.declaration.value.x.arithmetic.op != '=') {
                _ = v.appendManyCString(out, "/a ");
            }
            _ = v.appendSlice(u8, out, stmt.x.declaration.name);
            _ = v.append(u8, out, &equal);
            emitExpression(stmt.x.declaration.value, .declaration, ally, temporaries, out, call_labels);
            const binding = s.Binding{
                .name = stmt.x.declaration.name,
                .constant = stmt.x.declaration.constant,
                .read = false,
            };
            if (!v.append(s.Binding, names, &binding)) {
                @panic("Could not append name");
            }
            _ = v.appendManyCString(out, "\r\n");
        },
        .assignment => {
            _ = v.appendManyCString(out, "@set ");
            if (stmt.x.assignment.value.tag == .arithmetic) {
                _ = v.appendManyCString(out, "/a ");
            }
            _ = v.appendSlice(u8, out, stmt.x.assignment.name);
            _ = v.append(u8, out, &equal);
            emitExpression(stmt.x.assignment.value, .assignment, ally, temporaries, out, call_labels);
            var name_exists = false;
            for (names.slice.toZig()) |name| {
                if (name.name.eql(stmt.x.assignment.name)) name_exists = true;
            }
            if (!name_exists and outer_assignments != null) {
                var exists = false;
                for (outer_assignments.?.slice.toZig()) |outer| {
                    if (outer.x.assignment.name.eql(stmt.x.assignment.name)) {
                        exists = true;
                    }
                }
                if (!exists) {
                    const outer_stmt = p.Statement{
                        .tag = .assignment,
                        .x = .{ .assignment = .{
                            .name = stmt.x.assignment.name,
                            .value = .{
                                .tag = .identifier,
                                .x = .{ .identifier = stmt.x.assignment.name },
                            },
                        } },
                    };
                    if (!v.append(p.Statement, outer_assignments.?, &outer_stmt)) {
                        @panic("Failed to append outer assignment");
                    }
                }
            }
            _ = v.appendManyCString(out, "\r\n");
        },
        .inline_batch => {
            _ = v.appendSlice(u8, out, trim(stmt.x.inline_batch));
            _ = v.appendManyCString(out, "\r\n");
        },
        .block => {
            _ = v.appendManyCString(out, "@setlocal EnableDelayedExpansion\r\n");
            const new_outer_assignments_res =
                v.createVec(p.Statement, ally, 1);
            if (!new_outer_assignments_res.ok) @panic(std.mem.span(new_outer_assignments_res.x.err));
            var new_outer_assignments = new_outer_assignments_res.x.val;
            const block_names_res = v.createVec(s.Binding, ally, 8);
            if (!block_names_res.ok) @panic(std.mem.span(block_names_res.x.err));
            var block_names = block_names_res.x.val;
            for (stmt.x.block.statements.toZig()) |block_stmt| {
                emitStatement(block_stmt, ally, temporaries, out, branch_labels, loop_labels, call_labels, &block_names, &new_outer_assignments, functions);
            }

            _ = v.appendManyCString(out, "@endlocal");
            for (new_outer_assignments.slice.toZig()) |assignment| {
                _ = v.appendManyCString(out, " && set \"");
                _ = v.appendSlice(u8, out, assignment.x.assignment.name);
                _ = v.appendManyCString(out, "=%");
                _ = v.appendSlice(u8, out, assignment.x.assignment.value.x.identifier);
                _ = v.appendManyCString(out, "%\"");
            }
            _ = v.appendManyCString(out, "\r\n");
        },
        .@"if" => {
            var temporary_string: [128]u8 = undefined;
            var temporary_string_len: usize = 0;
            var branch_slice: Slice(u8) = undefined;
            const branch_label = branch_labels.*;
            branch_labels.* += 1;
            _ = v.appendManyCString(out, "@if not ");
            emitExpression(stmt.x.@"if".condition, .@"if", ally, temporaries, out, call_labels);
            _ = v.appendManyCString(out, " goto :");
            temporary_string_len = if (stmt.x.@"if".alternate != null)
                (std.fmt.bufPrint(&temporary_string, "_else{}_", .{branch_label}) catch unreachable).len
            else
                (std.fmt.bufPrint(&temporary_string, "_endif{}_", .{branch_label}) catch unreachable).len;
            branch_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, branch_slice);
            _ = v.appendManyCString(out, "\r\n");
            emitStatement(
                stmt.x.@"if".consequence.*,
                ally,
                temporaries,
                out,
                branch_labels,
                loop_labels,
                call_labels,
                names,
                outer_assignments,
                functions,
            );
            _ = v.appendManyCString(out, "@goto :");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endif{}_", .{branch_label}) catch unreachable).len;
            branch_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, branch_slice);
            _ = v.appendManyCString(out, "\r\n");
            if (stmt.x.@"if".alternate) |alt| {
                _ = alt; // autofix
                _ = v.appendManyCString(out, ":");
                temporary_string_len =
                    (std.fmt.bufPrint(&temporary_string, "_else{}_", .{branch_label}) catch unreachable).len;
                branch_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
                _ = v.appendSlice(u8, out, branch_slice);
                _ = v.appendManyCString(out, "\r\n");
                emitStatement(
                    stmt.x.@"if".alternate.?.*,
                    ally,
                    temporaries,
                    out,
                    branch_labels,
                    loop_labels,
                    call_labels,
                    names,
                    outer_assignments,
                    functions,
                );
            }
            _ = v.appendManyCString(out, ":");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endif{}_", .{branch_label}) catch unreachable).len;
            branch_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, branch_slice);
            _ = v.appendManyCString(out, "\r\n");
        },
        .@"while" => {
            var temporary_string: [128]u8 = undefined;
            var temporary_string_len: usize = 0;
            var loop_slice: Slice(u8) = undefined;
            const loop_label = loop_labels.*;
            loop_labels.* += 1;
            _ = v.appendManyCString(out, ":");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_while{}_", .{loop_label}) catch unreachable).len;
            loop_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, loop_slice);
            _ = v.appendManyCString(out, "\r\n@if not ");
            emitExpression(stmt.x.@"while".condition, .@"while", ally, temporaries, out, call_labels);
            _ = v.appendManyCString(out, " goto :");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endwhile{}_", .{loop_label}) catch unreachable).len;
            loop_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, loop_slice);
            _ = v.appendManyCString(out, "\r\n");
            emitStatement(
                stmt.x.@"while".body.*,
                ally,
                temporaries,
                out,
                branch_labels,
                loop_labels,
                call_labels,
                names,
                outer_assignments,
                functions,
            );
            _ = v.appendManyCString(out, "@goto :");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_while{}_", .{loop_label}) catch unreachable).len;
            loop_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, loop_slice);
            _ = v.appendManyCString(out, "\r\n:");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endwhile{}_", .{loop_label}) catch unreachable).len;
            loop_slice = .{ .ptr = &temporary_string, .len = temporary_string_len };
            _ = v.appendSlice(u8, out, loop_slice);
            _ = v.appendManyCString(out, "\r\n");
        },
        .@"return" => {
            const ftemporaries_res = v.createVec(p.Statement, ally, 2);
            if (!ftemporaries_res.ok) @panic(std.mem.span(ftemporaries_res.x.err));
            var ftemporaries = ftemporaries_res.x.val;
            const fbuffered_res = v.createVec(u8, ally, 32);
            if (!fbuffered_res.ok) @panic(std.mem.span(fbuffered_res.x.err));
            var fbuffered = fbuffered_res.x.val;
            _ = v.appendManyCString(&fbuffered, "@endlocal");
            if (stmt.x.@"return") |ret| {
                _ = v.appendManyCString(&fbuffered, " && set \"__ret__=");
                emitExpression(ret.*, .@"return", ally, &ftemporaries, &fbuffered, call_labels);
                for (ftemporaries.slice.toZig()) |tmp| {
                    emitStatement(
                        tmp,
                        ally,
                        &ftemporaries,
                        out,
                        branch_labels,
                        loop_labels,
                        call_labels,
                        names,
                        null,
                        &fbuffered,
                    );
                }
                _ = v.appendManyCString(&fbuffered, "\"");
            }
            _ = v.appendManyCString(&fbuffered, " && exit /b 0\r\n");
            v.shrinkToLength(u8, &fbuffered);
            _ = v.appendSlice(u8, out, fbuffered.slice);
        },
        .expression => b: {
            const expr = stmt.x.expression;
            // const stdout = getStdOut();
            switch (expr.tag) {
                .call => {
                    if (expr.x.call.callee.tag != .identifier) {
                        stdout.writeAll("Skipped unknown callee\n") catch {};
                        break :b;
                    }
                    if (expr.x.call.callee.x.identifier.eql("print")) {
                        _ = v.appendManyCString(out, "@echo");
                        for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param| {
                            _ = v.appendManyCString(out, " ");
                            emitExpression(param, .expression, ally, temporaries, out, call_labels);
                        }
                        _ = v.appendManyCString(out, "\r\n");
                    } else {
                        const call_res = v.createVec(u8, ally, 32);
                        if (!call_res.ok) @panic(std.mem.span(call_res.x.err));
                        var call = call_res.x.val;
                        _ = v.appendManyCString(&call, "@call :");
                        _ = v.appendSlice(u8, &call, expr.x.call.callee.x.identifier);
                        for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param| {
                            _ = v.appendManyCString(out, " ");
                            emitExpression(param, .expression, ally, temporaries, &call, call_labels);
                        }
                        _ = v.appendManyCString(&call, "\r\n");
                        v.shrinkToLength(u8, &call);
                        _ = v.appendSlice(u8, out, call.slice);
                    }
                },
                else => {
                    stdout.writeAll("Skipped unknown expression: ") catch {};
                    stdout.writeAll(expr.x.string.toZig()) catch {};
                    stdout.writeByte('\n') catch {};
                },
            }
        },
        .eof => @panic("StatementEOF"),
    }
}

pub export fn outputBatch(prog: p.Program, ally: a.Allocator, out: *v.Vec(u8)) void {
    _ = v.appendManyCString(out, "@setlocal EnableDelayedExpansion\r\n");
    _ = v.appendManyCString(out, "@pushd \"%~dp0\"\r\n\r\n");

    var temporaries = v.createVec(p.Statement, ally, 1);
    if (!temporaries.ok) @panic(std.mem.span(temporaries.x.err));
    var buffered = v.createVec(u8, ally, 32);
    if (!buffered.ok) @panic(std.mem.span(buffered.x.err));
    const functions_res = v.createVec(u8, ally, 32);
    if (!functions_res.ok) @panic(std.mem.span(functions_res.x.err));
    var functions = functions_res.x.val;
    var branch_labels: usize = 0;
    var loop_labels: usize = 0;
    var call_labels: usize = 0;
    const names_res = v.createVec(s.Binding, ally, 8);
    if (!names_res.ok) @panic(std.mem.span(names_res.x.err));
    var names = names_res.x.val;
    for (prog.statements.toZig()) |stmt| {
        emitStatement(
            stmt,
            ally,
            &temporaries.x.val,
            &buffered.x.val,
            &branch_labels,
            &loop_labels,
            &call_labels,
            &names,
            null,
            &functions,
        );
        for (temporaries.x.val.slice.toZig()) |tmp| {
            emitStatement(
                tmp,
                ally,
                &temporaries.x.val,
                out,
                &branch_labels,
                &loop_labels,
                &call_labels,
                &names,
                null,
                &functions,
            );
        }
        temporaries.x.val.slice.len = 0;
        _ = v.appendSlice(u8, out, buffered.x.val.slice);
        buffered.x.val.slice.len = 0;
    }
    _ = v.appendManyCString(out, "\r\n@popd\r\n");
    _ = v.appendManyCString(out, "@endlocal\r\n");
    _ = v.appendManyCString(out, "@exit /b 0\r\n\r\n");

    _ = v.appendSlice(u8, out, functions.slice);

    var allocation = Slice(p.Statement){
        .ptr = temporaries.x.val.slice.ptr,
        .len = temporaries.x.val.cap,
    };
    a.resizeAllocation(ally, p.Statement, &allocation, 0);
}
