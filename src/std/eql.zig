const std = @import("std");

const Slice = @import("Slice.zig").Slice;

pub export fn eql(a: Slice(u8), b: Slice(u8)) bool {
    return std.mem.eql(u8, a.ptr[0..a.len], b.ptr[0..b.len]);
}
