const std = @import("std");
const p = @import("parser.zig");
const s = @import("sema.zig");
const a = @import("../std/Allocator.zig");
const Slice = @import("../std/Slice.zig").Slice;
const v = @import("../std/Vec.zig");

pub fn emitExpression(
    expr: p.Expression,
    parent: p.StatementType,
    ally: std.mem.Allocator,
    temporaries: *std.ArrayList(p.Statement),
    out: *std.ArrayList(u8),
    call_labels: *usize,
) !void {
    switch (expr.tag) {
        .identifier => {
            if (parent == .@"if" or parent == .@"while") {
                try out.appendSlice("\"%");
                try out.appendSlice(expr.x.identifier);
                try out.appendSlice("%\"==\"true\"");
            } else {
                const perc: u8 = '%';
                try out.append(perc);
                try out.appendSlice(expr.x.identifier);
                try out.append(perc);
            }
        },
        .numeric => {
            try out.appendSlice(expr.x.number);
        },
        .string => {
            for (expr.x.string) |c| {
                try out.append(if (c == '\\') '^' else c);
            }
        },
        .call => {
            var call = try std.ArrayList(u8).initCapacity(ally, 32);
            try call.appendSlice("@call :");
            try call.appendSlice(expr.x.call.callee.x.identifier);
            for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param| {
                try call.append(' ');
                try emitExpression(param, parent, ally, temporaries, &call, call_labels);
            }
            try call.appendSlice("\r\n");
            const call_stmt = p.Statement{
                .tag = .inline_batch,
                .x = .{ .inline_batch = call.items },
            };
            try temporaries.append(call_stmt);
            var ret = try std.ArrayList(u8).initCapacity(ally, 32);
            const call_label = call_labels.*;
            call_labels.* += 1;
            ret.items.len += (std.fmt.bufPrint(
                ret.items.ptr[0..ret.capacity],
                "_ret{}_",
                .{call_label},
            ) catch unreachable).len;
            const ret_tmp = p.Statement{
                .tag = .declaration,
                .x = .{ .declaration = .{
                    .name = ret.items,
                    .value = .{
                        .tag = .identifier,
                        .x = .{ .identifier = "__ret__" },
                    },
                    .constant = true,
                } },
            };
            try temporaries.append(ret_tmp);
            try out.append('%');
            try out.appendSlice(ret.items);
            try out.append('%');
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
                    .{temporaries.items.len},
                ) catch unreachable).len;
                const tmp_str = try ally.alloc(u8, temporary_string_len);
                for (tmp_str, temporary_string[0..temporary_string_len]) |*dst, *src| {
                    dst.* = src.*;
                }
                var temporary: p.Statement = undefined;
                if (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!') {
                    const if_res = try ally.create(p.If);
                    if_res.condition = expr;
                    const con_res = try ally.create(p.Statement);
                    con_res.tag = .declaration;
                    con_res.x = .{
                        .declaration = .{
                            .name = tmp_str,
                            .value = .{
                                .tag = .string,
                                .x = .{ .string = "true" },
                            },
                            .constant = true,
                        },
                    };
                    if_res.consequence = con_res;
                    const alt_res = try ally.create(p.Statement);
                    alt_res.tag = .declaration;
                    alt_res.x = .{
                        .declaration = .{
                            .name = tmp_str,
                            .value = .{
                                .tag = .string,
                                .x = .{ .string = "false" },
                            },
                            .constant = true,
                        },
                    };
                    if_res.alternate = alt_res;
                    temporary = .{ .tag = .@"if", .x = .{ .@"if" = if_res } };
                } else {
                    temporary = .{
                        .tag = .declaration,
                        .x = .{ .declaration = .{
                            .name = tmp_str,
                            .value = expr,
                            .constant = true,
                        } },
                    };
                }
                try temporaries.append(temporary);
                try emitExpression(
                    .{ .tag = .identifier, .x = .{ .identifier = tmp_str } },
                    parent,
                    ally,
                    temporaries,
                    out,
                    call_labels,
                );
            } else {
                const quot: u8 = '"';
                if (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!') {
                    try out.append(quot);
                }
                try emitExpression(expr.x.arithmetic.left.*, .declaration, ally, temporaries, out, call_labels);
                if (expr.x.arithmetic.op == '=') {
                    try out.appendSlice("\"==\"");
                } else if (expr.x.arithmetic.op == '!') {
                    try out.appendSlice("\" NEQ \"");
                } else if (expr.x.arithmetic.op == '%') {
                    try out.appendSlice("%%");
                } else {
                    try out.append(expr.x.arithmetic.op);
                }
                try emitExpression(expr.x.arithmetic.right.*, .declaration, ally, temporaries, out, call_labels);
                if (expr.x.arithmetic.op == '=' or expr.x.arithmetic.op == '!') {
                    try out.append(quot);
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

pub fn emitStatement(
    stmt: p.Statement,
    ally: std.mem.Allocator,
    temporaries: *std.ArrayList(p.Statement),
    out: *std.ArrayList(u8),
    branch_labels: *usize,
    loop_labels: *usize,
    call_labels: *usize,
    names: *std.ArrayList(s.Binding),
    outer_assignments: ?*std.ArrayList(p.Statement),
    functions: *std.ArrayList(u8),
) !void {
    const stdout = std.io.getStdOut().writer();
    const equal: u8 = '=';
    switch (stmt.tag) {
        .declaration => b: {
            if (stmt.x.declaration.value.tag == .function) {
                try functions.append(':');
                try functions.appendSlice(stmt.x.declaration.name);
                try functions.appendSlice("\r\n");
                var tmp_str: [32]u8 = undefined;
                var tmp_str_len: usize = 0;
                var body_contents = try std.ArrayList(p.Statement).initCapacity(ally, 2);
                for (stmt.x.declaration.value.x.function_expression.parameters[0..stmt.x.declaration.value.x.function_expression.parameters_len], 0..) |param, i| {
                    tmp_str_len = (std.fmt.bufPrint(
                        &tmp_str,
                        "@set {s}=%~{}\r\n",
                        .{ param.x.identifier, i + 1 },
                    ) catch unreachable).len;
                    const str = try ally.alloc(u8, tmp_str_len);
                    for (tmp_str[0..tmp_str_len], 0..) |c, j| {
                        str[j] = c;
                    }
                    const decl = p.Statement{
                        .tag = .inline_batch,
                        .x = .{ .inline_batch = str },
                    };
                    try body_contents.append(decl);
                }
                try body_contents.appendSlice(stmt.x.declaration.value.x.function_expression.body.x.block.statements);
                var bodyBlockWithParams = p.Block{
                    .statements = try body_contents.toOwnedSlice(),
                };
                const bodyWithParams = p.Statement{
                    .tag = .block,
                    .x = .{ .block = &bodyBlockWithParams },
                };
                try emitStatement(
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
            try out.appendSlice("@set ");
            if (stmt.x.declaration.value.tag == .arithmetic and stmt.x.declaration.value.x.arithmetic.op != '=') {
                try out.appendSlice("/a ");
            }
            try out.appendSlice(stmt.x.declaration.name);
            try out.append(equal);
            try emitExpression(stmt.x.declaration.value, .declaration, ally, temporaries, out, call_labels);
            const binding = s.Binding{
                .name = stmt.x.declaration.name,
                .constant = stmt.x.declaration.constant,
                .read = false,
            };
            try names.append(binding);
            try out.appendSlice("\r\n");
        },
        .assignment => {
            try out.appendSlice("@set ");
            if (stmt.x.assignment.value.tag == .arithmetic) {
                try out.appendSlice("/a ");
            }
            try out.appendSlice(stmt.x.assignment.name);
            try out.append(equal);
            try emitExpression(stmt.x.assignment.value, .assignment, ally, temporaries, out, call_labels);
            var name_exists = false;
            for (names.items) |name| {
                if (std.mem.eql(u8, name.name, stmt.x.assignment.name)) name_exists = true;
            }
            if (!name_exists and outer_assignments != null) {
                var exists = false;
                for (outer_assignments.?.items) |outer| {
                    if (std.mem.eql(u8, outer.x.assignment.name, stmt.x.assignment.name)) {
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
                    try outer_assignments.?.append(outer_stmt);
                }
            }
            try out.appendSlice("\r\n");
        },
        .inline_batch => {
            try out.appendSlice(std.mem.trim(u8, stmt.x.inline_batch, &std.ascii.whitespace));
            try out.appendSlice("\r\n");
        },
        .block => {
            try out.appendSlice("@setlocal EnableDelayedExpansion\r\n");
            var new_outer_assignments = try std.ArrayList(p.Statement).initCapacity(ally, 1);
            var block_names = try std.ArrayList(s.Binding).initCapacity(ally, 8);
            for (stmt.x.block.statements) |block_stmt| {
                try emitStatement(block_stmt, ally, temporaries, out, branch_labels, loop_labels, call_labels, &block_names, &new_outer_assignments, functions);
            }

            try out.appendSlice("@endlocal");
            for (new_outer_assignments.items) |assignment| {
                try out.appendSlice(" && set \"");
                try out.appendSlice(assignment.x.assignment.name);
                try out.appendSlice("=%");
                try out.appendSlice(assignment.x.assignment.value.x.identifier);
                try out.appendSlice("%\"");
            }
            try out.appendSlice("\r\n");
        },
        .@"if" => {
            var temporary_string: [128]u8 = undefined;
            var temporary_string_len: usize = 0;
            const branch_label = branch_labels.*;
            branch_labels.* += 1;
            try out.appendSlice("@if not ");
            try emitExpression(stmt.x.@"if".condition, .@"if", ally, temporaries, out, call_labels);
            try out.appendSlice(" goto :");
            temporary_string_len = if (stmt.x.@"if".alternate != null)
                (std.fmt.bufPrint(&temporary_string, "_else{}_", .{branch_label}) catch unreachable).len
            else
                (std.fmt.bufPrint(&temporary_string, "_endif{}_", .{branch_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n");
            try emitStatement(
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
            try out.appendSlice("@goto :");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endif{}_", .{branch_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n");
            if (stmt.x.@"if".alternate) |alt| {
                _ = alt; // autofix
                try out.appendSlice(":");
                temporary_string_len =
                    (std.fmt.bufPrint(&temporary_string, "_else{}_", .{branch_label}) catch unreachable).len;
                try out.appendSlice(temporary_string[0..temporary_string_len]);
                try out.appendSlice("\r\n");
                try emitStatement(
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
            try out.appendSlice(":");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endif{}_", .{branch_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n");
        },
        .@"while" => {
            var temporary_string: [128]u8 = undefined;
            var temporary_string_len: usize = 0;
            const loop_label = loop_labels.*;
            loop_labels.* += 1;
            try out.appendSlice(":");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_while{}_", .{loop_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n@if not ");
            try emitExpression(stmt.x.@"while".condition, .@"while", ally, temporaries, out, call_labels);
            try out.appendSlice(" goto :");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endwhile{}_", .{loop_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n");
            try emitStatement(
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
            try out.appendSlice("@goto :");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_while{}_", .{loop_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n:");
            temporary_string_len =
                (std.fmt.bufPrint(&temporary_string, "_endwhile{}_", .{loop_label}) catch unreachable).len;
            try out.appendSlice(temporary_string[0..temporary_string_len]);
            try out.appendSlice("\r\n");
        },
        .@"return" => {
            var ftemporaries = try std.ArrayList(p.Statement).initCapacity(ally, 2);
            var fbuffered = try std.ArrayList(u8).initCapacity(ally, 32);
            try fbuffered.appendSlice("@endlocal");
            if (stmt.x.@"return") |ret| {
                try fbuffered.appendSlice(" && set \"__ret__=");
                try emitExpression(ret.*, .@"return", ally, &ftemporaries, &fbuffered, call_labels);
                for (ftemporaries.items) |tmp| {
                    try emitStatement(
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
                try fbuffered.appendSlice("\"");
            }
            try fbuffered.appendSlice(" && exit /b 0\r\n");
            try out.appendSlice(try fbuffered.toOwnedSlice());
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
                    if (std.mem.eql(u8, expr.x.call.callee.x.identifier, "print")) {
                        try out.appendSlice("@echo");
                        for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param| {
                            try out.appendSlice(" ");
                            try emitExpression(param, .expression, ally, temporaries, out, call_labels);
                        }
                        try out.appendSlice("\r\n");
                    } else {
                        var call = try std.ArrayList(u8).initCapacity(ally, 32);
                        try call.appendSlice("@call :");
                        try call.appendSlice(expr.x.call.callee.x.identifier);
                        for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param| {
                            try out.appendSlice(" ");
                            try emitExpression(param, .expression, ally, temporaries, &call, call_labels);
                        }
                        try call.appendSlice("\r\n");
                        try out.appendSlice(try call.toOwnedSlice());
                    }
                },
                else => {
                    try stdout.writeAll("Skipped unknown expression: ");
                    switch (expr.tag) {
                        .call => unreachable,
                        .numeric => try stdout.writeAll(expr.x.number),
                        .string => try stdout.writeAll(expr.x.string),
                        .identifier => try stdout.writeAll(expr.x.identifier),
                        else => try stdout.writeAll(@tagName(expr.tag)),
                    }
                    try stdout.writeByte('\n');
                },
            }
        },
        .eof => @panic("StatementEOF"),
    }
}

pub fn outputBatch(prog: p.Program, ally: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice("@setlocal EnableDelayedExpansion\r\n");
    try out.appendSlice("@pushd \"%~dp0\"\r\n\r\n");

    var temporaries = try std.ArrayList(p.Statement).initCapacity(ally, 1);
    var buffered = try std.ArrayList(u8).initCapacity(ally, 32);
    var functions = try std.ArrayList(u8).initCapacity(ally, 32);
    var branch_labels: usize = 0;
    var loop_labels: usize = 0;
    var call_labels: usize = 0;
    var names = try std.ArrayList(s.Binding).initCapacity(ally, 8);
    for (prog.statements) |stmt| {
        try emitStatement(
            stmt,
            ally,
            &temporaries,
            &buffered,
            &branch_labels,
            &loop_labels,
            &call_labels,
            &names,
            null,
            &functions,
        );
        for (temporaries.items) |tmp| {
            try emitStatement(
                tmp,
                ally,
                &temporaries,
                out,
                &branch_labels,
                &loop_labels,
                &call_labels,
                &names,
                null,
                &functions,
            );
        }
        temporaries.items.len = 0;
        try out.appendSlice(buffered.items);
        buffered.items.len = 0;
    }
    try out.appendSlice("\r\n@popd\r\n");
    try out.appendSlice("@endlocal\r\n");
    try out.appendSlice("@exit /b 0\r\n\r\n");

    try out.appendSlice(functions.items);

    temporaries.deinit();
}
