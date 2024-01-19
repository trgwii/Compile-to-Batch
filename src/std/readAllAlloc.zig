const std = @import("std");
const Result = @import("Result.zig").Result;
const Slice = @import("Slice.zig").Slice;
const alloc = @import("Allocator.zig");
const Allocator = alloc.Allocator;

const Res = Result(Slice(u8));

pub export fn readAllAlloc(ally: Allocator, f: *std.c.FILE) Res {
    const res = alloc.alloc(ally, u8, 16);
    if (!res.ok) return res;
    var str = res.x.val;
    var total_read: usize = 0;
    var read = std.c.fread(str.ptr + total_read, 1, str.len - total_read, f);
    while (read != 0) {
        total_read += read;
        if (str.len <= total_read) {
            const new_len = str.len * 2;
            alloc.resizeAllocation(ally, u8, &str, new_len);
            if (str.len != new_len) return Res.Err("could not expand string");
        }
        read = std.c.fread(str.ptr + total_read, 1, str.len - total_read, f);
    }
    alloc.resizeAllocation(ally, u8, &str, total_read);
    return Res.Ok(str);
}
