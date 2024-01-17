const std = @import("std");
const Result = @import("Result.zig").Result;
const Slice = @import("Slice.zig").Slice;
const Allocator = @import("Allocator.zig").Allocator;

const Res = Result(Slice(u8));

pub export fn readAllAlloc(ally: Allocator, f: *const std.c.FILE) Res {
    _ = ally;
    _ = f;
    // const str = ally.alloc(u8, 16) catch |err| return Res.fromZigErr(err);
    return Res.Err("TODO: implement this");
}