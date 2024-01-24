const std = @import("std");
const builtin = @import("builtin");
const vec = @import("../std/Vec.zig");
const Vec = vec.Vec;
const Slice = @import("../std/Slice.zig").Slice;
const Allocator = @import("../std/Allocator.zig").Allocator;
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
    },
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
            _ = fprintf(stdout, "Number(%1.%s)", expr.x.number.len, expr.x.number.ptr);
        },
        .string => {
            _ = fprintf(stdout, "String(%1.%s)", expr.x.string.len, expr.x.string.ptr);
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
            _ = fprintf(stdout, "Block {");
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

// TODO: rest of parser.c
// pub export fn parseParameters(ally: Allocator, it: *TokenIterator) Vec(Expression) {
//     const res = vec.createVec(Expression, ally, 1);
//     if (!res.ok) @panic(std.mem.span(res.x.err));
//     var parameters = res.x.val;
//     _ = parameters; // autofix
//     var param = tok.nextToken(it);
//     while (param.tag != .closeParen) {
//         if (param.tag == .eof) @panic("parseExpression: Unclosed open paren");
//         const expr = parseExpression(ally, it, param);
//     }
// }

// pub export fn parseExpression(ally: Allocator, it: *TokenIterator, t: tok.Token) Expression {
//     switch (t.tag) {
//         .number => {

//         }
//     }
// }
