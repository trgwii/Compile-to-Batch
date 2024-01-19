const std = @import("std");
const Slice = @import("../std/Slice.zig").Slice;

const TokenIterator = extern struct {
    data: Slice(u8),
    cur: usize = 0,
    line: usize = 1,
    col: usize = 1,
};

const TokenType = enum(c_int) {
    eof,
    ident,
    number,
    openParen,
    closeParen,
    openCurly,
    closeCurly,
    semi,
    comma,
    string,
    colon,
    equal,
    excl,
    star,
    plus,
    hyphen,
    slash,
    percent,
    inlineBatch,
    unknown,
};

const Token = extern struct {
    tag: TokenType,
    x: extern union {
        ident: Slice(u8),
        number: Slice(u8),
        string: Slice(u8),
        inline_batch: Slice(u8),
        unknown: extern struct {
            line: usize,
            col: usize,
            c: u8,
        },
    },
};

pub export fn printToken(t: Token) void {
    const out = std.io.getStdOut().writer();
    (switch (t.tag) {
        .eof => out.writeAll("(eof)"),
        .ident => out.print("Ident({s})", .{t.x.ident.ptr[0..t.x.ident.len]}),
        .number => out.print("Number({s})", .{t.x.number.ptr[0..t.x.number.len]}),
        .openParen => out.writeAll("OpenParen"),
        .closeParen => out.writeAll("CloseParen"),
        .openCurly => out.writeAll("OpenCurly"),
        .closeCurly => out.writeAll("CloseCurly"),
        .semi => out.writeAll("Semi"),
        .comma => out.writeAll("Comma"),
        .string => out.print("String({s})", .{t.x.string.ptr[0..t.x.string.len]}),
        .colon => out.writeAll("Colon"),
        .equal => out.writeAll("Equal"),
        .excl => out.writeAll("Excl"),
        .star => out.writeAll("Star"),
        .plus => out.writeAll("Plus"),
        .hyphen => out.writeAll("Hyphen"),
        .slash => out.writeAll("Slash"),
        .percent => out.writeAll("Percent"),
        .inlineBatch => out.print("Batch {{{s}}}", .{t.x.inline_batch.ptr[0..t.x.inline_batch.len]}),
        .unknown => out.print("(unknown:{}:{}: '{c}')", .{ t.x.unknown.line, t.x.unknown.col, t.x.unknown.c }),
    }) catch {};
}
