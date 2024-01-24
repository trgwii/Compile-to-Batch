const std = @import("std");
const Slice = @import("../std/Slice.zig").Slice;

pub const TokenIterator = extern struct {
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

pub const Token = extern struct {
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
    } = undefined,
};

pub export fn tokenizer(data: Slice(u8)) TokenIterator {
    return .{ .data = data };
}

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
        .string => out.print("String(\"{s}\")", .{t.x.string.ptr[0..t.x.string.len]}),
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

pub export fn updateLocationInfo(it: *TokenIterator, c: u8) void {
    if (c == '\n') {
        it.col = 0;
        it.line += 1;
    } else {
        it.col += 1;
    }
}

pub export fn tokenizerEnded(it: *TokenIterator) bool {
    return it.cur >= it.data.len;
}

pub export fn resetTokenizer(it: *TokenIterator) void {
    it.cur = 0;
    it.line = 1;
    it.col = 1;
}

pub export fn nextChar(it: *TokenIterator) u8 {
    const c = it.data.ptr[it.cur];
    it.cur += 1;
    updateLocationInfo(it, c);
    return c;
}

pub export fn skipWhitespace(it: *TokenIterator, _c: u8) u8 {
    var c = _c;
    while (std.ascii.isWhitespace(c)) {
        if (tokenizerEnded(it)) return 0;
        c = nextChar(it);
    }
    return c;
}

pub export fn nextToken(it: *TokenIterator) Token {
    if (tokenizerEnded(it)) return .{ .tag = .eof };

    var c = nextChar(it);
    c = skipWhitespace(it, c);
    if (c == 0) return .{ .tag = .eof };

    switch (c) {
        '(' => return .{ .tag = .openParen },
        ')' => return .{ .tag = .closeParen },
        '{' => return .{ .tag = .openCurly },
        '}' => return .{ .tag = .closeCurly },
        ';' => return .{ .tag = .semi },
        ',' => return .{ .tag = .comma },
        ':' => return .{ .tag = .colon },
        '=' => return .{ .tag = .equal },
        '!' => return .{ .tag = .excl },
        '*' => return .{ .tag = .star },
        '+' => return .{ .tag = .plus },
        '-' => return .{ .tag = .hyphen },
        '/' => return .{ .tag = .slash },
        '%' => return .{ .tag = .percent },
        else => {},
    }
    if (std.ascii.isAlphabetic(c) or c == '_') {
        const start = it.cur - 1;
        while (c == '_' or std.ascii.isAlphanumeric(c)) {
            if (tokenizerEnded(it)) break;
            c = nextChar(it);
        }
        it.cur -= 1;
        const ident = Slice(u8){
            .ptr = it.data.ptr + start,
            .len = it.cur - start,
        };
        if (std.mem.eql(u8, ident.ptr[0..ident.len], "batch")) {
            it.cur += 1;
            c = skipWhitespace(it, c);
            if (c == 0) return .{ .tag = .eof };
            if (c != '{') {
                @panic("batch keyword not followed by {");
            }
            var bracket_len: usize = 0;
            while (c == '{') {
                c = nextChar(it);
                if (tokenizerEnded(it)) return .{ .tag = .eof };
                bracket_len += 1;
            }
            const body_start = it.cur - 1;
            while (true) {
                c = nextChar(it);
                if (tokenizerEnded(it)) return .{
                    .tag = .inlineBatch,
                    .x = .{ .inline_batch = .{
                        .ptr = it.data.ptr + body_start,
                        .len = it.cur - body_start - bracket_len,
                    } },
                };
                if (c == '}') {
                    var ended = true;
                    for (0..bracket_len - 1) |_| {
                        c = nextChar(it);
                        if (tokenizerEnded(it)) return .{
                            .tag = .inlineBatch,
                            .x = .{ .inline_batch = .{
                                .ptr = it.data.ptr + body_start,
                                .len = it.cur - body_start - bracket_len,
                            } },
                        };
                        if (c != '}') {
                            ended = false;
                        }
                    }
                    if (ended) return .{
                        .tag = .inlineBatch,
                        .x = .{ .inline_batch = .{
                            .ptr = it.data.ptr + body_start,
                            .len = it.cur - body_start - bracket_len,
                        } },
                    };
                }
            }
        }

        return .{ .tag = .ident, .x = .{ .ident = ident } };
    }

    if (std.ascii.isDigit(c)) {
        const start = it.cur - 1;
        while (std.ascii.isDigit(c)) {
            if (tokenizerEnded(it)) break;
            c = nextChar(it);
        }
        it.cur -= 1;
        return .{
            .tag = .number,
            .x = .{ .number = .{
                .ptr = it.data.ptr + start,
                .len = it.cur - start,
            } },
        };
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

        return .{
            .tag = .string,
            .x = .{ .string = .{
                .ptr = it.data.ptr + start,
                .len = it.cur - 1 - start,
            } },
        };
    }

    return .{
        .tag = .unknown,
        .x = .{ .unknown = .{
            .line = it.line,
            .col = it.col,
            .c = c,
        } },
    };
}

pub export fn peekToken(it: *TokenIterator) Token {
    const cur = it.cur;
    const line = it.line;
    const col = it.col;
    const t = nextToken(it);
    it.cur = cur;
    it.line = line;
    it.col = col;
    return t;
}
