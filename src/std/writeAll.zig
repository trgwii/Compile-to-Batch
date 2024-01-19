const std = @import("std");
const Slice = @import("Slice.zig").Slice;

pub export fn writeAll(f: *std.c.FILE, str: Slice(u8)) void {
    var total_written: usize = 0;
    var written = std.c.fwrite(str.ptr + total_written, 1, str.len - total_written, f);
    while (written != 0) {
        total_written += written;
        written = std.c.fwrite(str.ptr + total_written, 1, str.len - total_written, f);
    }
}
