const std = @import("std");
const Slice = @import("../std/Slice.zig").Slice;
const vec = @import("../std/Vec.zig");
const alloc = @import("../std/Allocator.zig");
const Allocator = alloc.Allocator;
const p = @import("parser.zig");

pub const Binding = extern struct {
    name: Slice(u8),
    read: bool,
    constant: bool,
};

pub export fn nameListHasString(list: Slice(Binding), string: Slice(u8)) bool {
    for (list.toZig()) |binding| {
        if (binding.name.eql(string)) return true;
    }
    return false;
}

pub export fn analyzeExpression(ally: Allocator, names: Slice(Binding), expr: p.Expression) void {
    const stdout = std.io.getStdOut().writer();
    switch (expr.tag) {
        .identifier => {
            if (!nameListHasString(names, expr.x.identifier)) {
                if (!expr.x.identifier.eql("print")) {
                    stdout.print(
                        "Referring to undeclared name: {s}\n",
                        .{expr.x.identifier.toZig()},
                    ) catch {};
                }
            } else for (names.toZig()) |*binding|
                if (binding.name.eql(expr.x.identifier)) {
                    binding.read = true;
                };
        },
        .call => {
            analyzeExpression(ally, names, expr.x.call.callee.*);
            for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param|
                analyzeExpression(ally, names, param);
        },
        .arithmetic => {
            analyzeExpression(ally, names, expr.x.arithmetic.left.*);
            analyzeExpression(ally, names, expr.x.arithmetic.right.*);
        },
        .function => {
            const locals_res = vec.createVec(Binding, ally, 1);
            if (!locals_res.ok) @panic(std.mem.span(locals_res.x.err));
            var locals = locals_res.x.val;
            for (expr.x.function_expression.parameters[0..expr.x.function_expression.parameters_len]) |param| {
                const binding = Binding{
                    .name = param.x.identifier,
                    .constant = false,
                    .read = false,
                };
                if (!vec.append(Binding, &locals, &binding)) @panic("Failed to append to names");
            }
            analyzeStatement(&locals, expr.x.function_expression.body.*);
        },
        .numeric, .string => {},
    }
}

pub export fn analyzeStatement(names: *vec.Vec(Binding), stmt: p.Statement) void {
    const stdout = std.io.getStdOut().writer();
    switch (stmt.tag) {
        .declaration => {
            if (nameListHasString(names.slice, stmt.x.declaration.name)) {
                stdout.print(
                    "Double declaration of: {s}\n",
                    .{stmt.x.assignment.name.toZig()},
                ) catch {};
                return;
            }
            analyzeExpression(names.ally, names.slice, stmt.x.declaration.value);
            const binding = Binding{
                .name = stmt.x.declaration.name,
                .constant = stmt.x.declaration.constant,
                .read = false,
            };
            if (!vec.append(Binding, names, &binding)) @panic("analyze: Failed to append to names");
        },
        .assignment => {
            if (!nameListHasString(names.slice, stmt.x.assignment.name)) {
                stdout.print(
                    "Assignment to undeclared name: {s}\n",
                    .{stmt.x.assignment.name.toZig()},
                ) catch {};
            } else {
                for (names.slice.toZig()) |binding| {
                    if (binding.name.eql(stmt.x.assignment.name)) {
                        if (binding.constant) {
                            stdout.print(
                                "Assignment to constant: {s}\n",
                                .{stmt.x.assignment.name.toZig()},
                            ) catch {};
                        }
                    }
                }
            }
            analyzeExpression(names.ally, names.slice, stmt.x.assignment.value);
        },
        .expression => {
            analyzeExpression(names.ally, names.slice, stmt.x.expression);
        },
        .@"if" => {
            analyzeExpression(names.ally, names.slice, stmt.x.@"if".condition);
            analyzeStatement(names, stmt.x.@"if".consequence.*);
            if (stmt.x.@"if".alternate) |alt| analyzeStatement(names, alt.*);
        },
        .@"while" => {
            analyzeExpression(names.ally, names.slice, stmt.x.@"while".condition);
            analyzeStatement(names, stmt.x.@"while".body.*);
        },
        .block => {
            for (stmt.x.block.statements.toZig()) |s| analyzeStatement(names, s);
        },
        .@"return" => if (stmt.x.@"return") |ret|
            analyzeExpression(names.ally, names.slice, ret.*),
        .inline_batch => {},
        .eof => @panic("StatementEOF"),
    }
}

pub export fn analyze(ally: Allocator, prog: p.Program) void {
    const stdout = std.io.getStdOut().writer();
    const names_res = vec.createVec(Binding, ally, 4);
    if (!names_res.ok) @panic(std.mem.span(names_res.x.err));
    var names = names_res.x.val;
    for (prog.statements.toZig()) |stmt| {
        analyzeStatement(&names, stmt);
    }
    for (names.slice.toZig()) |b| {
        if (!b.read) {
            stdout.print("Unused {s}: {s}\n", .{
                if (b.constant) "constant" else "variable",
                b.name.toZig(),
            }) catch {};
        }
    }
}
