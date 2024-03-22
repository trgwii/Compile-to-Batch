const std = @import("std");
const Slice = @import("../std/Slice.zig").Slice;
const vec = @import("../std/Vec.zig");
const alloc = @import("../std/Allocator.zig");
const Allocator = alloc.Allocator;
const p = @import("parser.zig");

pub const Binding = struct {
    name: []const u8,
    read: bool,
    constant: bool,
};

pub fn nameListHasString(bindings: []const Binding, string: []const u8) bool {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.name, string)) return true;
    }
    return false;
}

pub fn analyzeExpression(ally: std.mem.Allocator, names: []Binding, expr: p.Expression) std.mem.Allocator.Error!void {
    const stdout = std.io.getStdOut().writer();
    switch (expr.tag) {
        .identifier => {
            if (!nameListHasString(names, expr.x.identifier)) {
                if (!std.mem.eql(u8, expr.x.identifier, "print")) {
                    stdout.print(
                        "Referring to undeclared name: {s}\n",
                        .{expr.x.identifier},
                    ) catch {};
                }
            } else for (names) |*binding|
                if (std.mem.eql(u8, binding.name, expr.x.identifier)) {
                    binding.read = true;
                };
        },
        .call => {
            try analyzeExpression(ally, names, expr.x.call.callee.*);
            for (expr.x.call.parameters[0..expr.x.call.parameters_len]) |param|
                try analyzeExpression(ally, names, param);
        },
        .arithmetic => {
            try analyzeExpression(ally, names, expr.x.arithmetic.left.*);
            try analyzeExpression(ally, names, expr.x.arithmetic.right.*);
        },
        .function => {
            var locals = try std.ArrayList(Binding).initCapacity(ally, 1);
            for (expr.x.function_expression.parameters[0..expr.x.function_expression.parameters_len]) |param| {
                const binding = Binding{
                    .name = param.x.identifier,
                    .constant = false,
                    .read = false,
                };
                try locals.append(binding);
            }
            try analyzeStatement(&locals, expr.x.function_expression.body.*);
        },
        .numeric, .string => {},
    }
}

pub fn analyzeStatement(names: *std.ArrayList(Binding), stmt: p.Statement) !void {
    const stdout = std.io.getStdOut().writer();
    switch (stmt.tag) {
        .declaration => {
            if (nameListHasString(names.items, stmt.x.declaration.name)) {
                stdout.print(
                    "Double declaration of: {s}\n",
                    .{stmt.x.declaration.name},
                ) catch {};
                return;
            }
            try analyzeExpression(names.allocator, names.items, stmt.x.declaration.value);
            const binding = Binding{
                .name = stmt.x.declaration.name,
                .constant = stmt.x.declaration.constant,
                .read = false,
            };
            try names.append(binding);
        },
        .assignment => {
            if (!nameListHasString(names.items, stmt.x.assignment.name)) {
                stdout.print(
                    "Assignment to undeclared name: {s}\n",
                    .{stmt.x.assignment.name},
                ) catch {};
            } else {
                for (names.items) |binding| {
                    if (std.mem.eql(u8, binding.name, stmt.x.assignment.name)) {
                        if (binding.constant) {
                            stdout.print(
                                "Assignment to constant: {s}\n",
                                .{stmt.x.assignment.name},
                            ) catch {};
                        }
                    }
                }
            }
            try analyzeExpression(names.allocator, names.items, stmt.x.assignment.value);
        },
        .expression => {
            try analyzeExpression(names.allocator, names.items, stmt.x.expression);
        },
        .@"if" => {
            try analyzeExpression(names.allocator, names.items, stmt.x.@"if".condition);
            try analyzeStatement(names, stmt.x.@"if".consequence.*);
            if (stmt.x.@"if".alternate) |alt| try analyzeStatement(names, alt.*);
        },
        .@"while" => {
            try analyzeExpression(names.allocator, names.items, stmt.x.@"while".condition);
            try analyzeStatement(names, stmt.x.@"while".body.*);
        },
        .block => {
            for (stmt.x.block.statements) |s| try analyzeStatement(names, s);
        },
        .@"return" => if (stmt.x.@"return") |ret|
            try analyzeExpression(names.allocator, names.items, ret.*),
        .inline_batch => {},
        .eof => @panic("StatementEOF"),
    }
}

pub fn analyze(ally: std.mem.Allocator, prog: p.Program) !void {
    const stdout = std.io.getStdOut().writer();
    var names = try std.ArrayList(Binding).initCapacity(ally, 4);
    for (prog.statements) |stmt| {
        try analyzeStatement(&names, stmt);
    }
    for (names.items) |b| {
        if (!b.read) {
            stdout.print("Unused {s}: {s}\n", .{
                if (b.constant) "constant" else "variable",
                b.name,
            }) catch {};
        }
    }
}
