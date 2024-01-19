const std = @import("std");

const Slice = @import("Slice.zig").Slice;
const Result = @import("Result.zig").Result;
const alloc = @import("Allocator.zig");
const Allocator = alloc.Allocator;
const readAllAlloc = @import("readAllAlloc.zig").readAllAlloc;

const Res = Result(Slice(u8));

pub export fn readFile(ally: Allocator, path: [*:0]const u8) Res {
    const f = std.c.fopen(path, "r") orelse return Res.Err("could not open file");
    var res = readAllAlloc(ally, f);
    if (std.c.fclose(f) != 0) {
        if (res.ok) alloc.resizeAllocation(ally, u8, &res.x.val, 0);
        return Res.Err("could not close file");
    }
    return res;
}
