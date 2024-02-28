const std = @import("std");
const Slice = @import("../std/Slice.zig").Slice;

pub const TokenIterator = struct {
    data: []const u8,
    cur: usize = 0,
    line: usize = 1,
    col: usize = 1,
};

pub const Token = union(enum) {
    eof,
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
};

pub fn printToken(t: Token) void {
    const out = std.io.getStdOut().writer();
    (switch (t) {
        .eof => out.writeAll("(eof)"),
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
    }) catch {};
}

pub fn updateLocationInfo(it: *TokenIterator, c: u8) void {
    if (c == '\n') {
        it.col = 0;
        it.line += 1;
    } else {
        it.col += 1;
    }
}

pub fn tokenizerEnded(it: *TokenIterator) bool {
    return it.cur >= it.data.len;
}

pub fn resetTokenizer(it: *TokenIterator) void {
    it.cur = 0;
    it.line = 1;
    it.col = 1;
}

pub fn nextChar(it: *TokenIterator) u8 {
    const c = it.data.ptr[it.cur];
    it.cur += 1;
    updateLocationInfo(it, c);
    return c;
}

pub fn skipWhitespace(it: *TokenIterator, _c: u8) u8 {
    var c = _c;
    while (std.ascii.isWhitespace(c)) {
        if (tokenizerEnded(it)) return 0;
        c = nextChar(it);
    }
    return c;
}

pub fn nextToken(it: *TokenIterator) Token {
    if (tokenizerEnded(it)) return .eof;

    var c = nextChar(it);
    c = skipWhitespace(it, c);
    if (c == 0) return .eof;

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
            if (tokenizerEnded(it)) break;
            c = nextChar(it);
        }
        it.cur -= 1;
        const ident = it.data[start..it.cur];
        if (std.mem.eql(u8, ident, "batch")) {
            it.cur += 1;
            c = skipWhitespace(it, c);
            if (c == 0) return .eof;
            if (c != '{') {
                @panic("batch keyword not followed by {");
            }
            var bracket_len: usize = 0;
            while (c == '{') {
                c = nextChar(it);
                if (tokenizerEnded(it)) return .eof;
                bracket_len += 1;
            }
            const body_start = it.cur - 1;
            while (true) {
                c = nextChar(it);
                if (tokenizerEnded(it)) return .{
                    .inline_batch = it.data[body_start .. it.cur - bracket_len],
                };
                if (c == '}') {
                    var ended = true;
                    for (0..bracket_len - 1) |_| {
                        c = nextChar(it);
                        if (tokenizerEnded(it)) return .{
                            .inline_batch = it.data[body_start .. it.cur - bracket_len],
                        };
                        if (c != '}') {
                            ended = false;
                        }
                    }
                    if (ended) return .{
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
            if (tokenizerEnded(it)) break;
            c = nextChar(it);
        }
        it.cur -= 1;
        return .{ .number = it.data[start..it.cur] };
    }

    if (c == '"') {
        const start = it.cur;
        var escape = false;
        while (true) {
            if (tokenizerEnded(it)) @panic("Tokenizer: unterminated string literal");
            c = nextChar(it);
            if (escape) {
                if (tokenizerEnded(it)) @panic("Tokenizer: unterminated string literal");
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

pub fn peekToken(it: *TokenIterator) Token {
    const cur = it.cur;
    const line = it.line;
    const col = it.col;
    const t = nextToken(it);
    it.cur = cur;
    it.line = line;
    it.col = col;
    return t;
}
