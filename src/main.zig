const std = @import("std");
comptime {
    std.testing.refAllDecls(@import("std/eql.zig"));
    std.testing.refAllDecls(@import("std/panic.zig"));
    std.testing.refAllDecls(@import("std/readAllAlloc.zig"));
    std.testing.refAllDecls(@import("std/readFile.zig"));
    std.testing.refAllDecls(@import("std/writeAll.zig"));

    std.testing.refAllDecls(@import("parser/tokenizer.zig"));
}

export fn setup_fault_handlers() void {
    std.debug.maybeEnableSegfaultHandler();
}

export fn printSize(bytes: usize) void {
    const out = std.io.getStdOut().writer();
    const fBytes: f64 = @floatFromInt(bytes);
    inline for (.{
        .{ "Mi", 1024 * 1024 },
        .{ "Ki", 1024 },
    }) |x| {
        if (bytes >= x[1]) {
            out.print("{d:.2}{s}B", .{ fBytes / x[1], x[0] }) catch {};
            return;
        }
    } else out.print("{}B", .{bytes}) catch {};
}

export fn startsWith(haystack: [*:0]const u8, needle: [*:0]const u8) bool {
    return std.mem.startsWith(u8, std.mem.span(haystack), std.mem.span(needle));
}

export fn str_len(s: [*:0]const u8) usize {
    return std.mem.len(s);
}

pub const _start = {};
pub const wWinMainCRTStartup = {};
