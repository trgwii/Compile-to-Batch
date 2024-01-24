const std = @import("std");
const builtin = @import("builtin");
const vec = @import("../std/Vec.zig");
const Vec = vec.Vec;
const Slice = @import("../std/Slice.zig").Slice;
const alloc = @import("../std/Allocator.zig");
const Allocator = alloc.Allocator;
const tok = @import("tokenizer.zig");
const TokenIterator = tok.TokenIterator;

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

const StatementType = enum(c_int) {
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

const If = extern struct {
    condition: Expression,
    consequence: *Statement,
    alternate: ?*Statement,
};

const While = extern struct {
    condition: Expression,
    body: *Statement,
};

const Block = extern struct {
    statements: Slice(Statement),
};

extern "c" fn fprintf(noalias stream: *std.c.FILE, [*:0]const u8, ...) c_int;
pub fn getStdOut() *std.c.FILE {
    if (builtin.target.os.tag == .windows) return @extern(
        *const fn (c_int) callconv(.C) *std.c.FILE,
        .{ .name = "__acrt_iob_func", .library_name = "c" },
    )(0);
    return @extern(**std.c.FILE, .{ .name = "stdout", .library_name = "c" }).*;
}

pub export fn printExpression(expr: Expression) void {
    const stdout = getStdOut();
    _ = fprintf(stdout, "Expr:");
    switch (expr.tag) {
        .call => {
            _ = fprintf(stdout, "Call:(");
            printExpression(expr.x.call.callee.*);
            _ = fprintf(stdout, ") with (");
            if (expr.x.call.parameters_len > 0) {
                printExpression(expr.x.call.parameters[0]);
            }
            for (1..expr.x.call.parameters_len) |i| {
                _ = fprintf(stdout, ", ");
                printExpression(expr.x.call.parameters[i]);
            }
            _ = fprintf(stdout, ")");
        },
        .identifier => {
            _ = fprintf(stdout, "Ident(%1.*s)", expr.x.identifier.len, expr.x.identifier.ptr);
        },
        .numeric => {
            _ = fprintf(stdout, "Number(%1.*s)", expr.x.number.len, expr.x.number.ptr);
        },
        .string => {
            _ = fprintf(stdout, "String(\"%1.*s\")", expr.x.string.len, expr.x.string.ptr);
        },
        .arithmetic => {
            _ = fprintf(stdout, "Arith(");
            printExpression(expr.x.arithmetic.left.*);
            _ = fprintf(stdout, " %c ", expr.x.arithmetic.op);
            printExpression(expr.x.arithmetic.right.*);
            _ = fprintf(stdout, ")");
        },
        .function => {
            _ = fprintf(stdout, "Function (");
            if (expr.x.function_expression.parameters_len > 0) {
                printExpression(expr.x.function_expression.parameters[0]);
            }
            for (1..expr.x.function_expression.parameters_len) |i| {
                _ = fprintf(stdout, ", ");
                printExpression(expr.x.function_expression.parameters[i]);
            }
            _ = fprintf(stdout, ") ");
            printStatement(expr.x.function_expression.body.*);
        },
    }
}

pub export fn printStatement(stmt: Statement) void {
    const stdout = getStdOut();
    switch (stmt.tag) {
        .expression => {
            printExpression(stmt.x.expression);
            _ = fprintf(stdout, "\n");
        },
        .declaration => {
            const decl = stmt.x.declaration;
            _ = fprintf(
                stdout,
                "%1.*s :%c ",
                decl.name.len,
                decl.name.ptr,
                @as(u8, if (decl.constant) ':' else '='),
            );
            printExpression(decl.value);
            _ = fprintf(stdout, "\n");
        },
        .assignment => {
            const assign = stmt.x.assignment;
            _ = fprintf(stdout, "%1.*s = ", assign.name.len, assign.name.ptr);
            printExpression(assign.value);
            _ = fprintf(stdout, "\n");
        },
        .inline_batch => {
            _ = fprintf(stdout, "Inline Batch {\n");
            _ = fprintf(
                stdout,
                "%1.*s",
                stmt.x.inline_batch.len,
                stmt.x.inline_batch.ptr,
            );
            _ = fprintf(stdout, "}\n");
        },
        .@"if" => {
            _ = fprintf(stdout, "If (");
            printExpression(stmt.x.@"if".condition);
            _ = fprintf(stdout, ") ");
            printStatement(stmt.x.@"if".consequence.*);
            if (stmt.x.@"if".alternate) |alt| {
                _ = fprintf(stdout, " else ");
                printStatement(alt.*);
            }
        },
        .@"while" => {
            _ = fprintf(stdout, "While (");
            printExpression(stmt.x.@"while".condition);
            _ = fprintf(stdout, ") ");
            printStatement(stmt.x.@"while".body.*);
        },
        .block => {
            _ = fprintf(stdout, "Block {\n");
            for (stmt.x.block.statements.ptr[0..stmt.x.block.statements.len]) |s| {
                printStatement(s);
            }
            _ = fprintf(stdout, "}\n");
        },
        .@"return" => {
            _ = fprintf(stdout, "Return (");
            if (stmt.x.@"return") |expr| printExpression(expr.*);
            _ = fprintf(stdout, ")\n");
        },
        .eof => {
            @panic("StatementEOF");
        },
    }
}

pub const Program = extern struct {
    statements: Slice(Statement),
};

pub export fn parseParameters(ally: Allocator, it: *TokenIterator) Vec(Expression) {
    const res = vec.createVec(Expression, ally, 1);
    if (!res.ok) @panic(std.mem.span(res.x.err));
    var parameters = res.x.val;
    var param = tok.nextToken(it);
    while (param.tag != .closeParen) {
        if (param.tag == .eof) @panic("parseExpression: Unclosed open paren");
        const expr = parseExpression(ally, it, param);
        const paramSep = tok.nextToken(it);
        if (paramSep.tag != .comma and paramSep.tag != .closeParen) {
            @panic("parseExpression: Parameter list expression not followed by comma or close paren ^");
        }
        if (!vec.append(Expression, &parameters, &expr)) {
            @panic("Failed to append to parameter list");
        }
        if (paramSep.tag == .closeParen) break;
        param = tok.nextToken(it);
    }
    vec.shrinkToLength(Expression, &parameters);
    return parameters;
}

pub export fn parseExpression(ally: Allocator, it: *TokenIterator, t: tok.Token) Expression {
    switch (t.tag) {
        .number => {
            const next = tok.peekToken(it);
            if (next.tag != .star and
                next.tag != .plus and
                next.tag != .excl and
                next.tag != .hyphen and
                next.tag != .slash and
                next.tag != .percent and
                next.tag != .equal)
                return .{ .tag = .numeric, .x = .{ .number = t.x.number } };
            _ = tok.nextToken(it);
            if (next.tag == .equal or next.tag == .excl) {
                if (tok.peekToken(it).tag != .equal) {
                    @panic("Invalid expression following <num> =");
                }
                // ==
                //  ^
                _ = tok.nextToken(it);
            }
            const lr_res = alloc.alloc(ally, Expression, 2);
            if (!lr_res.ok) @panic(std.mem.span(lr_res.x.err));
            const left = &lr_res.x.val.ptr[0];
            const right = &lr_res.x.val.ptr[1];
            left.* = parseExpression(ally, it, t);
            right.* = parseExpression(ally, it, tok.nextToken(it));
            return .{
                .tag = .arithmetic,
                .x = .{ .arithmetic = .{
                    .op = switch (next.tag) {
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
        .string => {
            return .{ .tag = .string, .x = .{ .string = t.x.string } };
        },
        .ident => {
            const next = tok.peekToken(it);
            if (next.tag == .star or
                next.tag == .plus or
                next.tag == .excl or
                next.tag == .hyphen or
                next.tag == .slash or
                next.tag == .percent or
                next.tag == .equal)
            {
                _ = tok.nextToken(it);
                if (next.tag == .equal or next.tag == .excl) {
                    if (tok.peekToken(it).tag != .equal) {
                        @panic("Invalid expression following <num> =");
                    }
                    // ==
                    //  ^
                    _ = tok.nextToken(it);
                }
                const lr_res = alloc.alloc(ally, Expression, 2);
                if (!lr_res.ok) @panic(std.mem.span(lr_res.x.err));
                const left = &lr_res.x.val.ptr[0];
                const right = &lr_res.x.val.ptr[1];
                left.* = .{
                    .tag = .identifier,
                    .x = .{ .identifier = t.x.ident },
                };
                right.* = parseExpression(ally, it, tok.nextToken(it));
                return .{
                    .tag = .arithmetic,
                    .x = .{ .arithmetic = .{
                        .op = switch (next.tag) {
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
            if (next.tag == .openParen) {
                // call expression
                _ = tok.nextToken(it);
                const parameters = parseParameters(ally, it);
                const callee_res = alloc.alloc(ally, Expression, 1);
                if (!callee_res.ok) @panic("parseExpression: Failed to allocate callee");
                const callee = &callee_res.x.val.ptr[0];
                callee.* = .{
                    .tag = .identifier,
                    .x = .{
                        .identifier = t.x.ident,
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
            return .{ .tag = .identifier, .x = .{ .identifier = t.x.ident } };
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
        .eof,
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
        .inlineBatch,
        .unknown,
        => {
            tok.printToken(t);
            @panic("\nparseExpression: Invalid TokenType ^");
        },
    }
}

pub export fn parseStatement(ally: Allocator, it: *TokenIterator) Statement {
    const snapshot = it.*;
    const t = tok.nextToken(it);
    switch (t.tag) {
        .ident, .number, .string => {
            if (t.tag == .ident and t.x.ident.eql("if")) {
                if (tok.peekToken(it).tag != .openParen) {
                    @panic("Missing ( after if");
                }
                _ = tok.nextToken(it); // (
                const condition = parseExpression(ally, it, tok.nextToken(it));
                if (tok.peekToken(it).tag != .closeParen) {
                    tok.printToken(tok.peekToken(it));
                    @panic("\nMissing ) after if condition");
                }
                _ = tok.nextToken(it); // )
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
                const elseToken = tok.peekToken(it);
                if (elseToken.tag == .ident and elseToken.x.ident.eql("else")) {
                    _ = tok.nextToken(it);
                    const alt_res = alloc.alloc(ally, Statement, 1);
                    if (!alt_res.ok) @panic(std.mem.span(alt_res.x.err));
                    const alternate = &alt_res.x.val.ptr[0];
                    alternate.* = parseStatement(ally, it);
                    if_statement.alternate = alternate;
                }
                return .{ .tag = .@"if", .x = .{ .@"if" = if_statement } };
            } else if (t.tag == .ident and t.x.ident.eql("while")) {
                if (tok.peekToken(it).tag != .openParen) {
                    @panic("Missing ( after while");
                }
                _ = tok.nextToken(it); // (
                const condition = parseExpression(ally, it, tok.nextToken(it));
                if (tok.peekToken(it).tag != .closeParen) {
                    tok.printToken(tok.peekToken(it));
                    @panic("\nMissing ) after while condition");
                }
                _ = tok.nextToken(it); // )
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
            } else if (t.tag == .ident and t.x.ident.eql("return")) {
                if (tok.peekToken(it).tag == .semi) {
                    _ = tok.nextToken(it);
                    return .{ .tag = .@"return", .x = .{ .@"return" = null } };
                }
                const ret_expr = alloc.alloc(ally, Expression, 1);
                if (!ret_expr.ok) @panic(std.mem.span(ret_expr.x.err));
                const ret = &ret_expr.x.val.ptr[0];
                ret.* = parseExpression(ally, it, tok.nextToken(it));
                const semi = tok.nextToken(it);
                if (semi.tag != .semi) {
                    tok.printToken(semi);
                    @panic("\nparse: Unknown token following expression statement ^");
                }
                return .{ .tag = .@"return", .x = .{ .@"return" = ret } };
            } else if (t.tag == .ident and tok.peekToken(it).tag == .colon) {
                _ = tok.nextToken(it); // :
                const afterColon = tok.peekToken(it);
                if (afterColon.tag != .equal and afterColon.tag != .colon) {
                    tok.printToken(tok.peekToken(it));
                    @panic("Invalid token following colon ^");
                }
                _ = tok.nextToken(it); // =
                const value = parseExpression(ally, it, tok.nextToken(it));
                const decl_stmt = Statement{
                    .tag = .declaration,
                    .x = .{ .declaration = .{
                        .name = t.x.ident,
                        .value = value,
                        .constant = afterColon.tag == .colon,
                    } },
                };
                const semi = tok.nextToken(it);
                if (semi.tag != .semi) {
                    tok.printToken(semi);
                    @panic("\nparse: Unknown token following expression statement ^");
                }
                return decl_stmt;
            } else if (t.tag == .ident and tok.peekToken(it).tag == .equal) {
                _ = tok.nextToken(it);
                const value = parseExpression(ally, it, tok.nextToken(it));
                const assign_stmt = Statement{
                    .tag = .assignment,
                    .x = .{ .assignment = .{
                        .name = t.x.ident,
                        .value = value,
                    } },
                };
                const semi = tok.nextToken(it);
                if (semi.tag != .semi) {
                    tok.printToken(semi);
                    @panic("\nparse: Unknown token following expression statement ^");
                }
                return assign_stmt;
            } else {
                const s = Statement{
                    .tag = .expression,
                    .x = .{ .expression = parseExpression(ally, it, t) },
                };
                const semi = tok.nextToken(it);
                if (semi.tag != .semi) {
                    tok.printToken(semi);
                    @panic("\nparse: Unknown token following expression statement ^");
                }
                return s;
            }
        },
        .inlineBatch => {
            return .{
                .tag = .inline_batch,
                .x = .{ .inline_batch = t.x.inline_batch },
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
            const closecurly = tok.peekToken(it);
            if (closecurly.tag != .closeCurly) {
                tok.printToken(closecurly);
                _ = std.c.printf("\n");
                @panic("\nparse: Unknown token following block ^");
            }
            _ = tok.nextToken(it); // }
            const block_res = alloc.alloc(ally, Block, 1);
            if (!block_res.ok) @panic(std.mem.span(block_res.x.err));
            vec.shrinkToLength(Statement, &statements);
            block_res.x.val.ptr[0].statements = statements.slice;
            return .{
                .tag = .block,
                .x = .{ .block = &block_res.x.val.ptr[0] },
            };
        },
        .eof,
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

pub export fn parse(ally: Allocator, it: *TokenIterator) Program {
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
