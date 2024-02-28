const std = @import("std");
const Slice = @import("../std/Slice.zig").Slice;

data: []const u8,
cur: usize = 0,
line: usize = 1,
col: usize = 1,

const Lexer = @This();

pub const Token = union(enum) {
    ident: []const u8,
    number: []const u8,
    openParen,
    closeParen,
    openCurly,
    closeCurly,
    semi,
    comma,
    string: []const u8,
    colon,
    equal,
    excl,
    star,
    plus,
    hyphen,
    slash,
    percent,
    inline_batch: []const u8,
    unknown: struct {
        line: usize,
        col: usize,
        c: u8,
    },
    pub fn print(t: Token) void {
        std.io.getStdOut().writer().print("{}", .{t}) catch {};
    }
    pub fn format(t: Token, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
        try switch (t) {
            .ident => |ident| out.print("Ident({s})", .{ident}),
            .number => |number| out.print("Number({s})", .{number}),
            .openParen => out.writeAll("OpenParen"),
            .closeParen => out.writeAll("CloseParen"),
            .openCurly => out.writeAll("OpenCurly"),
            .closeCurly => out.writeAll("CloseCurly"),
            .semi => out.writeAll("Semi"),
            .comma => out.writeAll("Comma"),
            .string => |string| out.print("String(\"{s}\")", .{string}),
            .colon => out.writeAll("Colon"),
            .equal => out.writeAll("Equal"),
            .excl => out.writeAll("Excl"),
            .star => out.writeAll("Star"),
            .plus => out.writeAll("Plus"),
            .hyphen => out.writeAll("Hyphen"),
            .slash => out.writeAll("Slash"),
            .percent => out.writeAll("Percent"),
            .inline_batch => |batch| out.print("Batch {{{s}}}", .{batch}),
            .unknown => |unknown| out.print("(unknown:{}:{}: '{c}')", .{ unknown.line, unknown.col, unknown.c }),
        };
    }
};

pub fn updateLocationInfo(it: *Lexer, c: u8) void {
    if (c == '\n') {
        it.col = 0;
        it.line += 1;
    } else {
        it.col += 1;
    }
}

pub fn ended(it: *Lexer) bool {
    return it.cur >= it.data.len;
}

pub fn reset(it: *Lexer) void {
    it.cur = 0;
    it.line = 1;
    it.col = 1;
}

pub fn nextChar(it: *Lexer) u8 {
    const c = it.data.ptr[it.cur];
    it.cur += 1;
    updateLocationInfo(it, c);
    return c;
}

pub fn skipWhitespace(it: *Lexer, _c: u8) u8 {
    var c = _c;
    while (std.ascii.isWhitespace(c)) {
        if (it.ended()) return 0;
        c = it.nextChar();
    }
    return c;
}

pub fn next(it: *Lexer) ?Token {
    if (it.ended()) return null;

    var c = it.nextChar();
    c = it.skipWhitespace(c);
    if (c == 0) return null;

    switch (c) {
        '(' => return .openParen,
        ')' => return .closeParen,
        '{' => return .openCurly,
        '}' => return .closeCurly,
        ';' => return .semi,
        ',' => return .comma,
        ':' => return .colon,
        '=' => return .equal,
        '!' => return .excl,
        '*' => return .star,
        '+' => return .plus,
        '-' => return .hyphen,
        '/' => return .slash,
        '%' => return .percent,
        else => {},
    }
    if (std.ascii.isAlphabetic(c) or c == '_') {
        const start = it.cur - 1;
        while (c == '_' or std.ascii.isAlphanumeric(c)) {
            if (it.ended()) break;
            c = nextChar(it);
        }
        it.cur -= 1;
        const ident = it.data[start..it.cur];
        if (std.mem.eql(u8, ident, "batch")) {
            it.cur += 1;
            c = skipWhitespace(it, c);
            if (c == 0) return null;
            if (c != '{') {
                @panic("batch keyword not followed by {");
            }
            var bracket_len: usize = 0;
            while (c == '{') {
                c = nextChar(it);
                if (it.ended()) return null;
                bracket_len += 1;
            }
            const body_start = it.cur - 1;
            while (true) {
                c = nextChar(it);
                if (it.ended()) return .{
                    .inline_batch = it.data[body_start .. it.cur - bracket_len],
                };
                if (c == '}') {
                    var end = true;
                    for (0..bracket_len - 1) |_| {
                        c = nextChar(it);
                        if (it.ended()) return .{
                            .inline_batch = it.data[body_start .. it.cur - bracket_len],
                        };
                        if (c != '}') {
                            end = false;
                        }
                    }
                    if (end) return .{
                        .inline_batch = it.data[body_start .. it.cur - bracket_len],
                    };
                }
            }
        }

        return .{ .ident = ident };
    }

    if (std.ascii.isDigit(c)) {
        const start = it.cur - 1;
        while (std.ascii.isDigit(c)) {
            if (it.ended()) break;
            c = nextChar(it);
        }
        it.cur -= 1;
        return .{ .number = it.data[start..it.cur] };
    }

    if (c == '"') {
        const start = it.cur;
        var escape = false;
        while (true) {
            if (it.ended()) @panic("Tokenizer: unterminated string literal");
            c = nextChar(it);
            if (escape) {
                if (it.ended()) @panic("Tokenizer: unterminated string literal");
                c = nextChar(it);
                escape = false;
            } else if (c == '\\') {
                escape = true;
            }
            if (!escape and c == '"') break;
        }

        return .{ .string = it.data[start .. it.cur - 1] };
    }

    return .{ .unknown = .{
        .line = it.line,
        .col = it.col,
        .c = c,
    } };
}

pub fn peek(it: *Lexer) ?Token {
    const cur = it.cur;
    const line = it.line;
    const col = it.col;
    const t = it.next();
    it.cur = cur;
    it.line = line;
    it.col = col;
    return t;
}
