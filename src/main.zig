const std = @import("std");
const Lexer = @import("parser/Lexer.zig");
const p = @import("parser/parser.zig");
const s = @import("parser/sema.zig");
const c = @import("parser/codegen.zig");

fn printSize(bytes: usize, writer: std.fs.File.Writer) !void {
    const fBytes: f64 = @floatFromInt(bytes);
    return inline for (.{
        .{ "Mi", 1024 * 1024 },
        .{ "Ki", 1024 },
    }) |x| {
        if (bytes >= x[1]) {
            break writer.print("{d:.2}{s}B", .{ fBytes / x[1], x[0] });
        }
    } else writer.print("{}B", .{bytes});
}

fn readFile(ally: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(ally, path, 1024 * 16);
}

pub fn main() !void {
    const stderr = std.io.getStdErr().writer();
    _ = stderr;
    const stdout = std.io.getStdOut().writer();

    var mem: [1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const allocator = fba.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const snapshot = fba.end_index;
    const no_color = env: {
        var env = try std.process.getEnvMap(allocator);
        defer fba.end_index = snapshot;
        break :env if (env.hash_map.get("NO_COLOR")) |value| value.len > 0 else false;
    };

    const gray: [*:0]const u8 = if (no_color) "" else "\x1b[90m";
    const red: [*:0]const u8 = if (no_color) "" else "\x1b[91m";
    const green: [*:0]const u8 = if (no_color) "" else "\x1b[92m";
    const yellow: [*:0]const u8 = if (no_color) "" else "\x1b[93m";
    const blue: [*:0]const u8 = if (no_color) "" else "\x1b[94m";
    const pink: [*:0]const u8 = if (no_color) "" else "\x1b[95m";
    const cyan: [*:0]const u8 = if (no_color) "" else "\x1b[96m";
    const reset: [*:0]const u8 = if (no_color) "" else "\x1b[0m";
    if (args.len < 3) @panic("usage: bc [inputfile.bb] [outputfile.cmd]");

    const data = try readFile(allocator, args[1]);
    defer allocator.free(data);

    try stdout.print("{s}---  SOURCE ---{s}\n", .{ gray, blue });
    try stdout.writeAll(data);
    try stdout.print("\n{s}--- /SOURCE ---\n", .{gray});

    try stdout.print("---  TOKENS ---{s}\n", .{green});

    var it = Lexer{ .data = data };
    var nl: usize = 0;
    while (it.next()) |t| {
        try t.print();
        nl += 1;
        if (nl >= 4) {
            nl = 0;
            try stdout.print("\n", .{});
        } else {
            try stdout.print("{s},\t{s}", .{ gray, green });
        }
    }

    try stdout.print("\n{s}--- /TOKENS ---\n", .{gray});

    try stdout.print("---  PARSE ---{s}\n", .{yellow});

    it.reset();

    const prog = try p.parse(allocator, &it);
    for (prog.statements) |stmt| {
        try p.printStatement(stmt);
    }

    try stdout.print("{s}--- /PARSE ---\n", .{gray});

    try stdout.print("---  ANALYZE ---{s}\n", .{red});
    try s.analyze(allocator, prog);
    try stdout.print("{s}--- /ANALYZE ---\n", .{gray});

    try stdout.print("---  CODEGEN ---{s}\n", .{pink});

    var outputVec = try std.ArrayList(u8).initCapacity(allocator, 512);
    try c.outputBatch(prog, allocator, &outputVec);
    const outputFile = try std.fs.cwd().createFile(args[2], .{});
    try outputFile.writeAll(outputVec.items);
    outputFile.close();
    try stdout.print("{s}Output Batch stored in {s}:{s}\n\n", .{ cyan, args[2], reset });
    const outputRes = try readFile(allocator, args[2]);
    defer allocator.free(outputRes);
    try stdout.print("{s}\n", .{outputRes});
    try stdout.print("{s}--- /CODEGEN ---\n", .{gray});

    try stdout.print("{s}Memory usage: ", .{cyan});
    try printSize(fba.end_index, stdout);
    try stdout.print(" / ", .{});
    try printSize(fba.buffer.len, stdout);
    try stdout.print("{s}\n", .{reset});
}
