const std = @import("std");
const a = @import("std/Allocator.zig");
const tok = @import("parser/tokenizer.zig");
const p = @import("parser/parser.zig");
const s = @import("parser/sema.zig");
const c = @import("parser/codegen.zig");
const readFile = @import("std/readFile.zig").readFile;
const writeAll = @import("std/writeAll.zig").writeAll;
const v = @import("std/Vec.zig");
comptime {
    std.testing.refAllDecls(@import("std/eql.zig"));
    std.testing.refAllDecls(@import("std/panic.zig"));
    std.testing.refAllDecls(@import("std/readAllAlloc.zig"));
    std.testing.refAllDecls(@import("std/readFile.zig"));
    std.testing.refAllDecls(@import("std/Vec.zig"));
    std.testing.refAllDecls(@import("std/writeAll.zig"));

    std.testing.refAllDecls(@import("parser/tokenizer.zig"));
    std.testing.refAllDecls(@import("parser/parser.zig"));
    std.testing.refAllDecls(@import("parser/sema.zig"));
    std.testing.refAllDecls(@import("parser/codegen.zig"));
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

export fn str_len(str: [*:0]const u8) usize {
    return std.mem.len(str);
}

pub const _start = {};
pub const wWinMainCRTStartup = {};

extern "c" fn fprintf(noalias stream: *std.c.FILE, [*:0]const u8, ...) c_int;
extern "c" fn fflush(stream: *std.c.FILE) c_int;
const getStdOut = p.getStdOut;

export fn main(argc: c_int, argv: [*:null]?[*:0]u8, envp: [*:null]?[*:0]u8) c_int {
    var no_color = false;
    var envp_i: usize = 0;
    while (envp[envp_i]) |str| : (envp_i += 1) {
        if (startsWith(str, "NO_COLOR=") and str_len(str) >= 10) no_color = true;
    }
    const gray: [*:0]const u8 = if (no_color) "" else "\x1b[90m";
    const red: [*:0]const u8 = if (no_color) "" else "\x1b[91m";
    const green: [*:0]const u8 = if (no_color) "" else "\x1b[92m";
    const yellow: [*:0]const u8 = if (no_color) "" else "\x1b[93m";
    const blue: [*:0]const u8 = if (no_color) "" else "\x1b[94m";
    const pink: [*:0]const u8 = if (no_color) "" else "\x1b[95m";
    const cyan: [*:0]const u8 = if (no_color) "" else "\x1b[96m";
    const reset: [*:0]const u8 = if (no_color) "" else "\x1b[0m";
    if (argc < 3) @panic("usage: bc [inputfile.bb] [outputfile.cmd]");

    var mem: [1024 * 1024]u8 = undefined;
    var state = a.Bump{ .mem = .{ .ptr = &mem, .len = mem.len } };
    const ally = a.Allocator{ .realloc = a.bumpRealloc, .state = &state };
    const res = readFile(ally, argv[1].?);

    const stdout = getStdOut();

    if (!res.ok) {
        _ = fprintf(stdout, "Error: %s: %s\n", res.x.err, argv[1]);
        return 1;
    }
    var data = res.x.val;

    _ = fprintf(stdout, "%s---  SOURCE ---%s\n", gray, blue);
    writeAll(stdout, data);
    _ = fprintf(stdout, "\n%s--- /SOURCE ---\n", gray);

    _ = fprintf(stdout, "---  TOKENS ---%s\n", green);
    _ = fflush(stdout);

    var it = tok.TokenIterator{ .data = data };
    var t = tok.nextToken(&it);
    var nl: usize = 0;
    while (t.tag != .eof) {
        tok.printToken(t);
        t = tok.nextToken(&it);
        if (t.tag != .eof) {
            nl += 1;
            if (nl >= 4) {
                nl = 0;
                _ = fprintf(stdout, "\n");
                _ = fflush(stdout);
            } else {
                _ = fprintf(stdout, "%s,\t%s", gray, green);
                _ = fflush(stdout);
            }
        }
    }

    _ = fprintf(stdout, "\n%s--- /TOKENS ---\n", gray);

    _ = fprintf(stdout, "---  PARSE ---%s\n", yellow);

    _ = fflush(stdout);

    tok.resetTokenizer(&it);

    const prog = p.parse(ally, &it);
    for (prog.statements.toZig()) |stmt| {
        p.printStatement(stmt);
    }

    _ = fprintf(stdout, "%s--- /PARSE ---\n", gray);

    _ = fprintf(stdout, "---  ANALYZE ---%s\n", red);
    _ = fflush(stdout);
    s.analyze(ally, prog);
    _ = fprintf(stdout, "%s--- /ANALYZE ---\n", gray);

    _ = fprintf(stdout, "---  CODEGEN ---%s\n", pink);
    _ = fflush(stdout);

    const outputVecRes = v.createVec(u8, ally, 512);
    if (!outputVecRes.ok) @panic(std.mem.span(outputVecRes.x.err));
    var outputVec = outputVecRes.x.val;
    c.outputBatch(prog, ally, &outputVec);
    const outputFile = std.c.fopen(argv[2].?, "w").?;
    writeAll(outputFile, outputVec.slice);
    _ = std.c.fclose(outputFile);
    _ = fprintf(stdout, "%sOutput Batch stored in %s:%s\n\n", cyan, argv[2], reset);
    const outputRes = readFile(ally, argv[2].?);
    if (!outputRes.ok) @panic(std.mem.span(outputRes.x.err));
    var outputData = outputRes.x.val;
    _ = fprintf(stdout, "%1.*s\n", outputData.len, outputData.ptr);
    _ = fprintf(stdout, "%s--- /CODEGEN ---\n", gray);

    _ = fprintf(stdout, "%sMemory usage: ", cyan);
    _ = fflush(stdout);
    printSize(state.cur);
    _ = fprintf(stdout, " / ");
    _ = fflush(stdout);
    printSize(state.mem.len);
    _ = fprintf(stdout, "%s\n", reset);
    _ = fflush(stdout);

    a.resizeAllocation(ally, u8, &outputData, 0);
    a.resizeAllocation(ally, u8, &data, 0);

    return 0;
}
