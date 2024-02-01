const std = @import("std");

pub fn Slice(comptime T: type) type {
    return extern struct {
        ptr: [*]T,
        len: usize,
        pub fn toZig(self: @This()) []T {
            return self.ptr[0..self.len];
        }
        pub fn fromZig(z: []T) @This() {
            return .{ .ptr = z.ptr, .len = z.len };
        }
        pub fn eql(self: @This(), other: anytype) bool {
            return std.mem.eql(T, self.toZig(), switch (@TypeOf(other)) {
                @This() => other.toZig(),
                []T, []const T => other,
                else => return self.eql(@as([]const T, other)),
            });
        }
    };
}
