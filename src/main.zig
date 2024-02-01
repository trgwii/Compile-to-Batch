const std = @import("std");
const a = @import("std/Allocator.zig");
const tok = @import("parser/tokenizer.zig");
const p = @import("parser/parser.zig");
const s = @import("parser/sema.zig");
const c = @import("parser/codegen.zig");
const Slice = @import("std/Slice.zig").Slice;
const v = @import("std/Vec.zig");
comptime {
    std.testing.refAllDecls(@import("std/Vec.zig"));

    std.testing.refAllDecls(@import("parser/tokenizer.zig"));
    std.testing.refAllDecls(@import("parser/parser.zig"));
    std.testing.refAllDecls(@import("parser/sema.zig"));
    std.testing.refAllDecls(@import("parser/codegen.zig"));
}

fn printSize(bytes: usize) void {
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

fn startsWith(haystack: [*:0]const u8, needle: [*:0]const u8) bool {
    return std.mem.startsWith(u8, std.mem.span(haystack), std.mem.span(needle));
}

fn str_len(str: [*:0]const u8) usize {
    return std.mem.len(str);
}

fn readFile(ally: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(ally, path, 1024 * 16);
}

pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    const args = argv[0..@intCast(argc)];
    const stderr = std.io.getStdErr().writer();
    const stdout = std.io.getStdOut().writer();

    var mem: [1024 * 1024]u8 = undefined;
    var state = a.Bump{ .mem = .{ .ptr = &mem, .len = mem.len } };
    const ally = a.Allocator{ .realloc = a.bumpRealloc, .state = &state };
    const allocator = ally.allocator();

    const no_color = env: {
        var env = std.process.getEnvMap(allocator) catch return 1;
        defer state.cur = 0;
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

    const data = readFile(allocator, std.mem.span(args[1])) catch |err| {
        stderr.print(
            "Error: {s}: {s}\n",
            .{ @errorName(err), std.mem.span(args[1]) },
        ) catch return 1;
        return 1;
    };
    defer allocator.free(data);

    stdout.print("{s}---  SOURCE ---{s}\n", .{ gray, blue }) catch {};
    stdout.writeAll(data) catch {};
    stdout.print("\n{s}--- /SOURCE ---\n", .{gray}) catch {};

    stdout.print("---  TOKENS ---{s}\n", .{green}) catch {};

    var it = tok.TokenIterator{ .data = Slice(u8).fromZig(data) };
    var t = tok.nextToken(&it);
    var nl: usize = 0;
    while (t.tag != .eof) {
        tok.printToken(t);
        t = tok.nextToken(&it);
        if (t.tag != .eof) {
            nl += 1;
            if (nl >= 4) {
                nl = 0;
                _ = stdout.print("\n", .{}) catch {};
            } else {
                _ = stdout.print("{s},\t{s}", .{ gray, green }) catch {};
            }
        }
    }

    stdout.print("\n{s}--- /TOKENS ---\n", .{gray}) catch {};

    stdout.print("---  PARSE ---{s}\n", .{yellow}) catch {};

    tok.resetTokenizer(&it);

    const prog = p.parse(ally, &it);
    for (prog.statements.toZig()) |stmt| {
        p.printStatement(stmt);
    }

    stdout.print("{s}--- /PARSE ---\n", .{gray}) catch {};

    stdout.print("---  ANALYZE ---{s}\n", .{red}) catch {};
    s.analyze(ally, prog);
    stdout.print("{s}--- /ANALYZE ---\n", .{gray}) catch {};

    stdout.print("---  CODEGEN ---{s}\n", .{pink}) catch {};

    const outputVecRes = v.createVec(u8, ally, 512);
    if (!outputVecRes.ok) @panic(std.mem.span(outputVecRes.x.err));
    var outputVec = outputVecRes.x.val;
    c.outputBatch(prog, ally, &outputVec);
    const outputFile = std.fs.cwd().createFile(std.mem.span(args[2]), .{}) catch return 1;
    outputFile.writeAll(outputVec.slice.toZig()) catch return 1;
    outputFile.close();
    stdout.print("{s}Output Batch stored in {s}:{s}\n\n", .{ cyan, args[2], reset }) catch {};
    const outputRes = readFile(allocator, std.mem.span(args[2])) catch |err| @panic(@errorName(err));
    defer allocator.free(outputRes);
    stdout.print("{s}\n", .{outputRes}) catch {};
    stdout.print("{s}--- /CODEGEN ---\n", .{gray}) catch {};

    stdout.print("{s}Memory usage: ", .{cyan}) catch {};
    printSize(state.cur);
    stdout.print(" / ", .{}) catch {};
    printSize(state.mem.len);
    stdout.print("{s}\n", .{reset}) catch {};

    return 0;
}
