const Slice = @import("Slice.zig").Slice;
const Result = @import("Result.zig").Result;

pub const Allocator = extern struct {
    realloc: *const fn (ptr: ?*anyopaque, size: usize, old_size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque,
    state: ?*anyopaque,
};

const Bump = extern struct {
    mem: Slice(u8),
    cur: usize,
};

pub export fn alloc_(ally: Allocator, size: usize, length: usize) Result(Slice(u8)) {
    const ptr = ally.realloc(null, size * length, 0, ally.state);
    if (ptr == null) return Result(Slice(u8)).Err("alloc: out of memory");
    return Result(Slice(u8)).Ok(.{ .ptr = @ptrCast(ptr.?), .len = length });
}

pub fn alloc(ally: Allocator, comptime T: type, length: usize) Result(Slice(T)) {
    return @bitCast(alloc_(ally, @sizeOf(T), length));
}

pub export fn resizeAllocation_(
    ally: Allocator,
    allocation: *Slice(u8),
    size: usize,
    new_length: usize,
) void {
    const ptr = ally.realloc(
        allocation.ptr,
        size * new_length,
        size * allocation.len,
        ally.state,
    );
    if (ptr == null and new_length != 0) return;
    allocation.ptr = @ptrCast(ptr.?);
    allocation.len = new_length;
}

pub fn resizeAllocation(ally: Allocator, comptime T: type, allocation: *Slice(T), new_length: usize) void {
    resizeAllocation_(ally, @ptrCast(allocation), @sizeOf(T), new_length);
}

export fn bumpRealloc(ptr: ?*anyopaque, size: usize, old_size: usize, state: ?*anyopaque) ?*anyopaque {
    const bump = @as(*Bump, @alignCast(@ptrCast(state.?)));
    if (size == 0) {
        if (@intFromPtr(bump.mem.ptr) + bump.cur - old_size == @intFromPtr(ptr)) {
            // free in place
            bump.cur -= old_size;
        }
        // free of earlier allocation, waste memory
        return null;
    }
    if (ptr != null and @intFromPtr(bump.mem.ptr) + bump.cur - old_size != @intFromPtr(ptr)) {
        const new_ptr = bumpRealloc(null, size, 0, state);
        if (new_ptr == null) return null;
        for (0..size) |i|
            @as([*]u8, @ptrCast(new_ptr))[i] = @as([*]const u8, @ptrCast(ptr))[i];
        return new_ptr;
    }

    const Align = (8 - ((@intFromPtr(bump.mem.ptr) - bump.cur) % 8)) % 8;
    if (bump.cur - old_size + size + Align > bump.mem.len) {
        // OOM
        return null;
    }
    const result = bump.mem.ptr + bump.cur - old_size + Align;
    bump.cur +%= size -% old_size + Align;
    return result;
}
