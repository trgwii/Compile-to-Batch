const std = @import("std");
const builtin = @import("builtin");
const vec = @import("../std/Vec.zig");
const Vec = vec.Vec;
const Slice = @import("../std/Slice.zig").Slice;
const alloc = @import("../std/Allocator.zig");
const Allocator = alloc.Allocator;
const Lexer = @import("Lexer.zig");

const ExpressionType = enum(c_int) {
    call,
    identifier,
    numeric,
    string,
    arithmetic,
    function,
};

pub const Expression = extern struct {
    tag: ExpressionType,
    x: extern union {
        call: extern struct {
            callee: *Expression,
            parameters: [*]Expression,
            parameters_len: usize,
        },
        number: Slice(u8),
        string: Slice(u8),
        identifier: Slice(u8),
        arithmetic: extern struct {
            op: u8,
            left: *Expression,
            right: *Expression,
        },
        function_expression: extern struct {
            parameters: [*]Expression,
            parameters_len: usize,
            body: *Statement,
        },
    },
};

const Declaration = extern struct {
    name: Slice(u8),
    value: Expression,
    constant: bool,
};

const Assignment = extern struct {
    name: Slice(u8),
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

pub const Statement = extern struct {
    tag: StatementType,
    x: extern union {
        expression: Expression,
        declaration: Declaration,
        assignment: Assignment,
        inline_batch: Slice(u8),
        @"if": *If,
        @"while": *While,
        block: *Block,
        @"return": ?*Expression,
    } = undefined,
};

pub const If = extern struct {
    condition: Expression,
    consequence: *Statement,
    alternate: ?*Statement,
};

const While = extern struct {
    condition: Expression,
    body: *Statement,
};

pub const Block = extern struct {
    statements: Slice(Statement),
};

pub export fn printExpression(expr: Expression) void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("Expr:") catch {};
    switch (expr.tag) {
        .call => {
            stdout.writeAll("Call:(") catch {};
            printExpression(expr.x.call.callee.*);
            stdout.writeAll(") with (") catch {};
            if (expr.x.call.parameters_len > 0) {
                printExpression(expr.x.call.parameters[0]);
            }
            for (1..expr.x.call.parameters_len) |i| {
                stdout.writeAll(", ") catch {};
                printExpression(expr.x.call.parameters[i]);
            }
            stdout.writeAll(")") catch {};
        },
        .identifier => {
            stdout.print("Ident({s})", .{expr.x.identifier.toZig()}) catch {};
        },
        .numeric => {
            stdout.print("Number({s})", .{expr.x.number.toZig()}) catch {};
        },
        .string => {
            stdout.print("String(\"{s}\")", .{expr.x.string.toZig()}) catch {};
        },
        .arithmetic => {
            stdout.writeAll("Arith(") catch {};
            printExpression(expr.x.arithmetic.left.*);
            stdout.writeByte(expr.x.arithmetic.op) catch {};
            printExpression(expr.x.arithmetic.right.*);
            stdout.writeByte(')') catch {};
        },
        .function => {
            stdout.writeAll("Function (") catch {};
            if (expr.x.function_expression.parameters_len > 0) {
                printExpression(expr.x.function_expression.parameters[0]);
            }
            for (1..expr.x.function_expression.parameters_len) |i| {
                stdout.writeAll(", ") catch {};
                printExpression(expr.x.function_expression.parameters[i]);
            }
            stdout.writeAll(") ") catch {};
            printStatement(expr.x.function_expression.body.*);
        },
    }
}

pub export fn printStatement(stmt: Statement) void {
    const stdout = std.io.getStdOut().writer();
    switch (stmt.tag) {
        .expression => {
            printExpression(stmt.x.expression);
            stdout.writeByte('\n') catch {};
        },
        .declaration => {
            const decl = stmt.x.declaration;
            stdout.print("{s} :{c} ", .{
                decl.name.toZig(),
                @as(u8, if (decl.constant) ':' else '='),
            }) catch {};
            printExpression(decl.value);
            stdout.writeByte('\n') catch {};
        },
        .assignment => {
            const assign = stmt.x.assignment;
            stdout.print("{s} = ", .{assign.name.toZig()}) catch {};
            printExpression(assign.value);
            stdout.writeByte('\n') catch {};
        },
        .inline_batch => {
            stdout.writeAll("Inline Batch {\n") catch {};
            stdout.writeAll(stmt.x.inline_batch.toZig()) catch {};
            stdout.writeAll("}\n") catch {};
        },
        .@"if" => {
            stdout.writeAll("If (") catch {};
            printExpression(stmt.x.@"if".condition);
            stdout.writeAll(") ") catch {};
            printStatement(stmt.x.@"if".consequence.*);
            if (stmt.x.@"if".alternate) |alt| {
                stdout.writeAll(" else ") catch {};
                printStatement(alt.*);
            }
        },
        .@"while" => {
            stdout.writeAll("While (") catch {};
            printExpression(stmt.x.@"while".condition);
            stdout.writeAll(") ") catch {};
            printStatement(stmt.x.@"while".body.*);
        },
        .block => {
            stdout.writeAll("Block {\n") catch {};
            for (stmt.x.block.statements.ptr[0..stmt.x.block.statements.len]) |s| {
                printStatement(s);
            }
            stdout.writeAll("}\n") catch {};
        },
        .@"return" => {
            stdout.writeAll("Return (") catch {};
            if (stmt.x.@"return") |expr| printExpression(expr.*);
            stdout.writeAll(")\n") catch {};
        },
        .eof => {
            @panic("StatementEOF");
        },
    }
}

pub const Program = extern struct {
    statements: Slice(Statement),
};

pub export fn parseParameters(ally: Allocator, it: *Lexer) Vec(Expression) {
    const res = vec.createVec(Expression, ally, 1);
    if (!res.ok) @panic(std.mem.span(res.x.err));
    var parameters = res.x.val;
    var param = it.next().?;
    while (param != .closeParen) : (param = it.next().?) {
        const expr = parseExpression(ally, it, param);
        const paramSep = it.next().?;
        if (paramSep != .comma and paramSep != .closeParen) {
            @panic("parseExpression: Parameter list expression not followed by comma or close paren ^");
        }
        if (!vec.append(Expression, &parameters, &expr)) {
            @panic("Failed to append to parameter list");
        }
        if (paramSep == .closeParen) break;
    }
    vec.shrinkToLength(Expression, &parameters);
    return parameters;
}

pub fn parseExpression(ally: Allocator, it: *Lexer, t: Lexer.Token) Expression {
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
                return .{ .tag = .numeric, .x = .{ .number = Slice(u8).fromZig(@constCast(number)) } };
            _ = it.next().?;
            if (next == .equal or next == .excl) {
                if (Lexer.peek(it).? != .equal) {
                    @panic("Invalid expression following <num> =");
                }
                // ==
                //  ^
                _ = it.next().?;
            }
            const lr_res = alloc.alloc(ally, Expression, 2);
            if (!lr_res.ok) @panic(std.mem.span(lr_res.x.err));
            const left = &lr_res.x.val.ptr[0];
            const right = &lr_res.x.val.ptr[1];
            left.* = parseExpression(ally, it, t);
            right.* = parseExpression(ally, it, it.next().?);
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
            return .{ .tag = .string, .x = .{ .string = Slice(u8).fromZig(@constCast(string)) } };
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
                const lr_res = alloc.alloc(ally, Expression, 2);
                if (!lr_res.ok) @panic(std.mem.span(lr_res.x.err));
                const left = &lr_res.x.val.ptr[0];
                const right = &lr_res.x.val.ptr[1];
                left.* = .{
                    .tag = .identifier,
                    .x = .{ .identifier = Slice(u8).fromZig(@constCast(ident)) },
                };
                right.* = parseExpression(ally, it, it.next().?);
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
                const parameters = parseParameters(ally, it);
                const callee_res = alloc.alloc(ally, Expression, 1);
                if (!callee_res.ok) @panic("parseExpression: Failed to allocate callee");
                const callee = &callee_res.x.val.ptr[0];
                callee.* = .{
                    .tag = .identifier,
                    .x = .{
                        .identifier = Slice(u8).fromZig(@constCast(ident)),
                    },
                };
                return .{
                    .tag = .call,
                    .x = .{ .call = .{
                        .callee = callee,
                        .parameters = parameters.slice.ptr,
                        .parameters_len = parameters.slice.len,
                    } },
                };
            }
            return .{ .tag = .identifier, .x = .{ .identifier = Slice(u8).fromZig(@constCast(ident)) } };
        },
        .openParen => {
            const parameters = parseParameters(ally, it);
            const body_res = alloc.alloc(ally, Statement, 1);
            if (!body_res.ok) @panic(std.mem.span(body_res.x.err));
            const body = &body_res.x.val.ptr[0];
            body.* = parseStatement(ally, it);
            return .{
                .tag = .function,
                .x = .{ .function_expression = .{
                    .parameters = parameters.slice.ptr,
                    .parameters_len = parameters.slice.len,
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
            std.io.getStdOut().writer().print("{}", .{t}) catch {};
            @panic("\nparseExpression: Invalid TokenType ^");
        },
    }
}

pub export fn parseStatement(ally: Allocator, it: *Lexer) Statement {
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
                const condition = parseExpression(ally, it, it.next().?);
                if (Lexer.peek(it).? != .closeParen) {
                    Lexer.peek(it).?.print();
                    @panic("\nMissing ) after if condition");
                }
                _ = it.next().?; // )
                const if_res = alloc.alloc(ally, If, 1);
                if (!if_res.ok) @panic(std.mem.span(if_res.x.err));
                const if_statement = &if_res.x.val.ptr[0];
                const cons_res = alloc.alloc(ally, Statement, 1);
                if (!cons_res.ok) @panic(std.mem.span(cons_res.x.err));
                const consequence = &cons_res.x.val.ptr[0];
                consequence.* = parseStatement(ally, it);
                if_statement.condition = condition;
                if_statement.consequence = consequence;
                if_statement.alternate = null;
                const elseToken = Lexer.peek(it).?;
                if (elseToken == .ident and std.mem.eql(u8, elseToken.ident, "else")) {
                    _ = it.next().?;
                    const alt_res = alloc.alloc(ally, Statement, 1);
                    if (!alt_res.ok) @panic(std.mem.span(alt_res.x.err));
                    const alternate = &alt_res.x.val.ptr[0];
                    alternate.* = parseStatement(ally, it);
                    if_statement.alternate = alternate;
                }
                return .{ .tag = .@"if", .x = .{ .@"if" = if_statement } };
            } else if (t == .ident and std.mem.eql(u8, str, "while")) {
                if (Lexer.peek(it).? != .openParen) {
                    @panic("Missing ( after while");
                }
                _ = it.next().?; // (
                const condition = parseExpression(ally, it, it.next().?);
                if (Lexer.peek(it).? != .closeParen) {
                    Lexer.peek(it).?.print();
                    @panic("\nMissing ) after while condition");
                }
                _ = it.next().?; // )
                const while_res = alloc.alloc(ally, While, 1);
                if (!while_res.ok) @panic(std.mem.span(while_res.x.err));
                const while_statement = &while_res.x.val.ptr[0];
                const body_res = alloc.alloc(ally, Statement, 1);
                if (!body_res.ok) @panic(std.mem.span(body_res.x.err));
                const body = &body_res.x.val.ptr[0];
                body.* = parseStatement(ally, it);
                while_statement.condition = condition;
                while_statement.body = body;
                return .{ .tag = .@"while", .x = .{ .@"while" = while_statement } };
            } else if (t == .ident and std.mem.eql(u8, str, "return")) {
                if (Lexer.peek(it).? == .semi) {
                    _ = it.next().?;
                    return .{ .tag = .@"return", .x = .{ .@"return" = null } };
                }
                const ret_expr = alloc.alloc(ally, Expression, 1);
                if (!ret_expr.ok) @panic(std.mem.span(ret_expr.x.err));
                const ret = &ret_expr.x.val.ptr[0];
                ret.* = parseExpression(ally, it, it.next().?);
                const semi = it.next().?;
                if (semi != .semi) {
                    semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return .{ .tag = .@"return", .x = .{ .@"return" = ret } };
            } else if (t == .ident and Lexer.peek(it).? == .colon) {
                _ = it.next().?; // :
                const afterColon = Lexer.peek(it).?;
                if (afterColon != .equal and afterColon != .colon) {
                    Lexer.peek(it).?.print();
                    @panic("Invalid Lexeren following colon ^");
                }
                _ = it.next().?; // =
                const value = parseExpression(ally, it, it.next().?);
                const decl_stmt = Statement{
                    .tag = .declaration,
                    .x = .{ .declaration = .{
                        .name = Slice(u8).fromZig(@constCast(str)),
                        .value = value,
                        .constant = afterColon == .colon,
                    } },
                };
                const semi = it.next().?;
                if (semi != .semi) {
                    semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return decl_stmt;
            } else if (t == .ident and Lexer.peek(it).? == .equal) {
                _ = it.next().?;
                const value = parseExpression(ally, it, it.next().?);
                const assign_stmt = Statement{
                    .tag = .assignment,
                    .x = .{ .assignment = .{
                        .name = Slice(u8).fromZig(@constCast(t.ident)),
                        .value = value,
                    } },
                };
                const semi = it.next().?;
                if (semi != .semi) {
                    semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return assign_stmt;
            } else {
                const s = Statement{
                    .tag = .expression,
                    .x = .{ .expression = parseExpression(ally, it, t) },
                };
                const semi = it.next().?;
                if (semi != .semi) {
                    semi.print();
                    @panic("\nparse: Unknown Lexeren following expression statement ^");
                }
                return s;
            }
        },
        .inline_batch => |batch| {
            return .{
                .tag = .inline_batch,
                .x = .{ .inline_batch = Slice(u8).fromZig(@constCast(batch)) },
            };
        },
        .openCurly => {
            const statements_res = vec.createVec(Statement, ally, 4);
            if (!statements_res.ok) @panic(std.mem.span(statements_res.x.err));
            var statements = statements_res.x.val;
            var stmt = parseStatement(ally, it);
            while (stmt.tag != .eof) {
                printStatement(stmt);
                if (!vec.append(Statement, &statements, &stmt)) {
                    @panic("Failed to append statement in block");
                }
                stmt = parseStatement(ally, it);
            }
            const closecurly = Lexer.peek(it).?;
            if (closecurly != .closeCurly) {
                std.io.getStdOut().writer().print("{}\n", .{closecurly}) catch {};
                @panic("\nparse: Unknown Lexeren following block ^");
            }
            _ = it.next().?; // }
            const block_res = alloc.alloc(ally, Block, 1);
            if (!block_res.ok) @panic(std.mem.span(block_res.x.err));
            vec.shrinkToLength(Statement, &statements);
            block_res.x.val.ptr[0].statements = statements.slice;
            return .{
                .tag = .block,
                .x = .{ .block = &block_res.x.val.ptr[0] },
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

pub export fn parse(ally: Allocator, it: *Lexer) Program {
    const res = vec.createVec(Statement, ally, 16);
    if (!res.ok) @panic("parse: Failed to alloc statements");
    var statements = res.x.val;
    var stmt = parseStatement(ally, it);
    while (stmt.tag != .eof) {
        if (!vec.append(Statement, &statements, &stmt)) {
            @panic("Failed to append to statement list");
        }
        stmt = parseStatement(ally, it);
    }
    vec.shrinkToLength(Statement, &statements);
    return .{ .statements = statements.slice };
}
