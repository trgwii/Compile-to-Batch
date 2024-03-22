const std = @import("std");
const builtin = @import("builtin");
const Lexer = @import("Lexer.zig");

const ExpressionType = enum(c_int) {
    call,
    identifier,
    numeric,
    string,
    arithmetic,
    function,
};

pub const Expression = struct {
    tag: ExpressionType,
    x: union {
        call: struct {
            callee: *Expression,
            parameters: [*]const Expression,
            parameters_len: usize,
        },
        number: []const u8,
        string: []const u8,
        identifier: []const u8,
        arithmetic: struct {
            op: u8,
            left: *Expression,
            right: *Expression,
        },
        function_expression: struct {
            parameters: [*]const Expression,
            parameters_len: usize,
            body: *Statement,
        },
    },
};

const Declaration = struct {
    name: []const u8,
    value: Expression,
    constant: bool,
};

const Assignment = struct {
    name: []const u8,
    value: Expression,
};

pub const StatementType = enum(c_int) {
    eof,
    expression,
    declaration,
    assignment,
    inline_batch,
    block,
    @"if",
    @"while",
    @"return",
};

pub const Statement = struct {
    tag: StatementType,
    x: union {
        expression: Expression,
        declaration: Declaration,
        assignment: Assignment,
        inline_batch: []const u8,
        @"if": *If,
        @"while": *While,
        block: *Block,
        @"return": ?*Expression,
    } = undefined,
};

pub const If = struct {
    condition: Expression,
    consequence: *Statement,
    alternate: ?*Statement,
};

const While = struct {
    condition: Expression,
    body: *Statement,
};

pub const Block = struct {
    statements: []const Statement,
};

pub fn printExpression(expr: Expression) (error{StatementEOF} || std.fs.File.WriteError)!void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Expr:");
    switch (expr.tag) {
        .call => {
            try stdout.writeAll("Call:(");
            try printExpression(expr.x.call.callee.*);
            try stdout.writeAll(") with (");
            if (expr.x.call.parameters_len > 0) {
                try printExpression(expr.x.call.parameters[0]);
            }
            for (1..expr.x.call.parameters_len) |i| {
                try stdout.writeAll(", ");
                try printExpression(expr.x.call.parameters[i]);
            }
            try stdout.writeAll(")");
        },
        .identifier => {
            try stdout.print("Ident({s})", .{expr.x.identifier});
        },
        .numeric => {
            try stdout.print("Number({s})", .{expr.x.number});
        },
        .string => {
            try stdout.print("String(\"{s}\")", .{expr.x.string});
        },
        .arithmetic => {
            try stdout.writeAll("Arith(");
            try printExpression(expr.x.arithmetic.left.*);
            try stdout.writeByte(expr.x.arithmetic.op);
            try printExpression(expr.x.arithmetic.right.*);
            try stdout.writeByte(')');
        },
        .function => {
            try stdout.writeAll("Function (");
            if (expr.x.function_expression.parameters_len > 0) {
                try printExpression(expr.x.function_expression.parameters[0]);
            }
            for (1..expr.x.function_expression.parameters_len) |i| {
                try stdout.writeAll(", ");
                try printExpression(expr.x.function_expression.parameters[i]);
            }
            try stdout.writeAll(") ");
            try printStatement(expr.x.function_expression.body.*);
        },
    }
}

pub fn printStatement(stmt: Statement) (error{StatementEOF} || std.fs.File.WriteError)!void {
    const stdout = std.io.getStdOut().writer();
    switch (stmt.tag) {
        .expression => {
            try printExpression(stmt.x.expression);
            try stdout.writeByte('\n');
        },
        .declaration => {
            const decl = stmt.x.declaration;
            try stdout.print("{s} :{c} ", .{
                decl.name,
                @as(u8, if (decl.constant) ':' else '='),
            });
            try printExpression(decl.value);
            try stdout.writeByte('\n');
        },
        .assignment => {
            const assign = stmt.x.assignment;
            try stdout.print("{s} = ", .{assign.name});
            try printExpression(assign.value);
            try stdout.writeByte('\n');
        },
        .inline_batch => {
            try stdout.writeAll("Inline Batch {\n");
            try stdout.writeAll(stmt.x.inline_batch);
            try stdout.writeAll("}\n");
        },
        .@"if" => {
            try stdout.writeAll("If (");
            try printExpression(stmt.x.@"if".condition);
            try stdout.writeAll(") ");
            try printStatement(stmt.x.@"if".consequence.*);
            if (stmt.x.@"if".alternate) |alt| {
                try stdout.writeAll(" else ");
                try printStatement(alt.*);
            }
        },
        .@"while" => {
            try stdout.writeAll("While (");
            try printExpression(stmt.x.@"while".condition);
            try stdout.writeAll(") ");
            try printStatement(stmt.x.@"while".body.*);
        },
        .block => {
            try stdout.writeAll("Block {\n");
            for (stmt.x.block.statements.ptr[0..stmt.x.block.statements.len]) |s| {
                try printStatement(s);
            }
            try stdout.writeAll("}\n");
        },
        .@"return" => {
            try stdout.writeAll("Return (");
            if (stmt.x.@"return") |expr| try printExpression(expr.*);
            try stdout.writeAll(")\n");
        },
        .eof => return error.StatementEOF,
    }
}

pub const Program = struct {
    statements: []const Statement,
};

pub fn parseParameters(ally: std.mem.Allocator, it: *Lexer) ![]const Expression {
    var parameters = try std.ArrayList(Expression).initCapacity(ally, 1);
    var param = it.next().?;
    while (param != .closeParen) : (param = it.next().?) {
        const expr = try parseExpression(ally, it, param);
        const paramSep = it.next().?;
        if (paramSep != .comma and paramSep != .closeParen) {
            @panic("parseExpression: Parameter list expression not followed by comma or close paren ^");
        }
        try parameters.append(expr);
        if (paramSep == .closeParen) break;
    }
    return parameters.toOwnedSlice();
}

pub fn parseExpression(ally: std.mem.Allocator, it: *Lexer, t: Lexer.Token) (error{StatementEOF} || std.mem.Allocator.Error || std.fs.File.WriteError)!Expression {
    switch (t) {
        .number => |number| {
            const next = Lexer.peek(it).?;
            if (next != .star and
                next != .plus and
                next != .excl and
                next != .hyphen and
                next != .slash and
                next != .percent and
                next != .equal)
                return .{ .tag = .numeric, .x = .{ .number = number } };
            _ = it.next().?;
            if (next == .equal or next == .excl) {
                if (Lexer.peek(it).? != .equal) {
                    @panic("Invalid expression following <num> =");
                }
                // ==
                //  ^
                _ = it.next().?;
            }
            const lr = try ally.alloc(Expression, 2);
            const left = &lr[0];
            const right = &lr[1];
            left.* = try parseExpression(ally, it, t);
            right.* = try parseExpression(ally, it, it.next().?);
            return .{
                .tag = .arithmetic,
                .x = .{ .arithmetic = .{
                    .op = switch (next) {
                        .star => '*',
                        .plus => '+',
                        .hyphen => '-',
                        .equal => '=',
                        .excl => '!',
                        .percent => '%',
                        else => '/',
                    },
                    .left = left,
                    .right = right,
                } },
            };
        },
        .string => |string| {
            return .{ .tag = .string, .x = .{ .string = string } };
        },
        .ident => |ident| {
            const next = Lexer.peek(it).?;
            if (next == .star or
                next == .plus or
                next == .excl or
                next == .hyphen or
                next == .slash or
                next == .percent or
                next == .equal)
            {
                _ = it.next().?;
                if (next == .equal or next == .excl) {
                    if (Lexer.peek(it).? != .equal) {
                        @panic("Invalid expression following <num> =");
                    }
                    // ==
                    //  ^
                    _ = it.next().?;
                }
                const lr = try ally.alloc(Expression, 2);
                const left = &lr[0];
                const right = &lr[1];
                left.* = .{
                    .tag = .identifier,
                    .x = .{ .identifier = ident },
                };
                right.* = try parseExpression(ally, it, it.next().?);
                return .{
                    .tag = .arithmetic,
                    .x = .{ .arithmetic = .{
                        .op = switch (next) {
                            .star => '*',
                            .plus => '+',
                            .hyphen => '-',
                            .equal => '=',
                            .excl => '!',
                            .percent => '%',
                            else => '/',
                        },
                        .left = left,
                        .right = right,
                    } },
                };
            }
            if (next == .openParen) {
                // call expression
                _ = it.next().?;
                const parameters = try parseParameters(ally, it);
                const callee = try ally.create(Expression);
                callee.* = .{
                    .tag = .identifier,
                    .x = .{ .identifier = ident },
                };
                return .{
                    .tag = .call,
                    .x = .{ .call = .{
                        .callee = callee,
                        .parameters = parameters.ptr,
                        .parameters_len = parameters.len,
                    } },
                };
            }
            return .{ .tag = .identifier, .x = .{ .identifier = ident } };
        },
        .openParen => {
            const parameters = try parseParameters(ally, it);
            const body = try ally.create(Statement);
            body.* = try parseStatement(ally, it);
            return .{
                .tag = .function,
                .x = .{ .function_expression = .{
                    .parameters = parameters.ptr,
                    .parameters_len = parameters.len,
                    .body = body,
                } },
            };
        },
        .closeParen,
        .openCurly,
        .closeCurly,
        .semi,
        .comma,
        .colon,
        .equal,
        .excl,
        .star,
        .plus,
        .hyphen,
        .slash,
        .percent,
        .inline_batch,
        .unknown,
        => {
            try std.io.getStdOut().writer().print("{}", .{t});
            @panic("\nparseExpression: Invalid TokenType ^");
        },
    }
}

pub fn parseStatement(ally: std.mem.Allocator, it: *Lexer) !Statement {
    const snapshot = it.*;
    const t = it.next() orelse {
        it.* = snapshot; // restore
        return .{ .tag = .eof };
    };

    switch (t) {
        .ident, .number, .string => |str| {
            if (t == .ident and std.mem.eql(u8, str, "if")) {
                if (Lexer.peek(it).? != .openParen) {
                    @panic("Missing ( after if");
                }
                _ = it.next().?; // (
                const condition = try parseExpression(ally, it, it.next().?);
                if (Lexer.peek(it).? != .closeParen) {
                    try Lexer.peek(it).?.print();
                    @panic("\nMissing ) after if condition");
                }
                _ = it.next().?; // )
                const if_statement = try ally.create(If);
                const consequence = try ally.create(Statement);
                consequence.* = try parseStatement(ally, it);
                if_statement.condition = condition;
                if_statement.consequence = consequence;
                if_statement.alternate = null;
                const elseToken = Lexer.peek(it).?;
                if (elseToken == .ident and std.mem.eql(u8, elseToken.ident, "else")) {
                    _ = it.next().?;
                    const alternate = try ally.create(Statement);
                    alternate.* = try parseStatement(ally, it);
                    if_statement.alternate = alternate;
                }
                return .{ .tag = .@"if", .x = .{ .@"if" = if_statement } };
            } else if (t == .ident and std.mem.eql(u8, str, "while")) {
                if (Lexer.peek(it).? != .openParen) {
                    @panic("Missing ( after while");
                }
                _ = it.next().?; // (
                const condition = try parseExpression(ally, it, it.next().?);
                if (Lexer.peek(it).? != .closeParen) {
                    try Lexer.peek(it).?.print();
                    @panic("\nMissing ) after while condition");
                }
                _ = it.next().?; // )
                const while_statement = try ally.create(While);
                const body = try ally.create(Statement);
                body.* = try parseStatement(ally, it);
                while_statement.condition = condition;
                while_statement.body = body;
                return .{ .tag = .@"while", .x = .{ .@"while" = while_statement } };
            } else if (t == .ident and std.mem.eql(u8, str, "return")) {
                if (Lexer.peek(it).? == .semi) {
                    _ = it.next().?;
                    return .{ .tag = .@"return", .x = .{ .@"return" = null } };
                }
                const ret = try ally.create(Expression);
                ret.* = try parseExpression(ally, it, it.next().?);
                const semi = it.next().?;
                if (semi != .semi) {
                    try semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return .{ .tag = .@"return", .x = .{ .@"return" = ret } };
            } else if (t == .ident and Lexer.peek(it).? == .colon) {
                _ = it.next().?; // :
                const afterColon = Lexer.peek(it).?;
                if (afterColon != .equal and afterColon != .colon) {
                    try Lexer.peek(it).?.print();
                    @panic("Invalid Lexeren following colon ^");
                }
                _ = it.next().?; // =
                const value = try parseExpression(ally, it, it.next().?);
                const decl_stmt = Statement{
                    .tag = .declaration,
                    .x = .{ .declaration = .{
                        .name = str,
                        .value = value,
                        .constant = afterColon == .colon,
                    } },
                };
                const semi = it.next().?;
                if (semi != .semi) {
                    try semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return decl_stmt;
            } else if (t == .ident and Lexer.peek(it).? == .equal) {
                _ = it.next().?;
                const value = try parseExpression(ally, it, it.next().?);
                const assign_stmt = Statement{
                    .tag = .assignment,
                    .x = .{ .assignment = .{
                        .name = t.ident,
                        .value = value,
                    } },
                };
                const semi = it.next().?;
                if (semi != .semi) {
                    try semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return assign_stmt;
            } else {
                const s = Statement{
                    .tag = .expression,
                    .x = .{ .expression = try parseExpression(ally, it, t) },
                };
                const semi = it.next().?;
                if (semi != .semi) {
                    try semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return s;
            }
        },
        .inline_batch => |batch| {
            return .{
                .tag = .inline_batch,
                .x = .{ .inline_batch = batch },
            };
        },
        .openCurly => {
            var statements = try std.ArrayList(Statement).initCapacity(ally, 4);
            var stmt = try parseStatement(ally, it);
            while (stmt.tag != .eof) {
                try printStatement(stmt);
                try statements.append(stmt);
                stmt = try parseStatement(ally, it);
            }
            const closecurly = Lexer.peek(it).?;
            if (closecurly != .closeCurly) {
                try std.io.getStdOut().writer().print("{}\n", .{closecurly});
                @panic("\nparse: Unknown Lexeren following block ^");
            }
            _ = it.next().?; // }
            const block = try ally.create(Block);
            block.* = .{ .statements = try statements.toOwnedSlice() };
            return .{
                .tag = .block,
                .x = .{ .block = block },
            };
        },
        .openParen,
        .closeParen,
        .closeCurly,
        .semi,
        .comma,
        .colon,
        .equal,
        .excl,
        .star,
        .plus,
        .hyphen,
        .slash,
        .percent,
        .unknown,
        => {
            it.* = snapshot; // restore
            return .{ .tag = .eof };
        },
    }
    unreachable;
}

pub fn parse(ally: std.mem.Allocator, it: *Lexer) !Program {
    var statements = try std.ArrayList(Statement).initCapacity(ally, 16);
    var stmt = try parseStatement(ally, it);
    while (stmt.tag != .eof) {
        try statements.append(stmt);
        stmt = try parseStatement(ally, it);
    }
    return .{ .statements = try statements.toOwnedSlice() };
}
