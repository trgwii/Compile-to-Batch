const std = @import("std");
const Slice = @import("Slice.zig").Slice;
const Result = @import("Result.zig").Result;
const alloc = @import("Allocator.zig");
const Allocator = alloc.Allocator;

pub fn Vec(comptime T: type) type {
    return extern struct {
        slice: Slice(T),
        ally: Allocator,
        cap: usize,
    };
}

pub export fn append_(v: *Vec(u8), size: usize, item: [*]const u8) bool {
    if (v.slice.len >= v.cap) {
        var allocated = Slice(u8){
            .ptr = v.slice.ptr,
            .len = v.cap,
        };
        alloc.resizeAllocation_(v.ally, &allocated, size, v.cap * 2);
        v.slice.ptr = allocated.ptr;
        v.cap = allocated.len;
    }

    if (v.slice.len >= v.cap) return false;

    for (0..size) |i| {
        v.slice.ptr[v.slice.len * size + i] = item[i];
    }
    v.slice.len += 1;
    return true;
}

pub fn append(comptime T: type, v: *Vec(T), item: *const T) bool {
    return append_(@ptrCast(v), @sizeOf(T), @ptrCast(item));
}

pub export fn appendMany_(v: *Vec(u8), size: usize, items: [*]const u8, items_len: usize) bool {
    for (0..items_len) |i| {
        if (!append_(v, size, items + (i * size))) return false;
    }
    return true;
}

pub fn appendMany(comptime T: type, v: *Vec(T), items: [*]const T, items_len: usize) bool {
    return appendMany_(@ptrCast(v), @sizeOf(T), @ptrCast(items), items_len);
}

pub fn appendSlice(comptime T: type, v: *Vec(T), items: Slice(T)) bool {
    return appendMany(T, v, items.ptr, items.len);
}

pub fn appendManyCString(v: *Vec(u8), items: [*:0]const u8) bool {
    return appendMany(u8, v, items, std.mem.len(items));
}

pub export fn createVec_(ally: Allocator, size: usize, cap: usize) Result(Vec(u8)) {
    const Res = Result(Vec(u8));
    const res = alloc.alloc_(ally, size, cap);
    if (!res.ok) return Res.Err(res.x.err);
    const v = Vec(u8){
        .slice = .{ .ptr = res.x.val.ptr, .len = 0 },
        .ally = ally,
        .cap = cap,
    };
    return Res.Ok(v);
}

pub fn createVec(comptime T: type, ally: Allocator, cap: usize) Result(Vec(T)) {
    return @bitCast(createVec_(ally, @sizeOf(T), cap));
}

pub export fn shrinkToLength_(v: *Vec(u8), size: usize) void {
    var allocation = Slice(u8){
        .ptr = v.slice.ptr,
        .len = v.cap,
    };
    alloc.resizeAllocation_(v.ally, &allocation, size, v.slice.len);
    v.slice.ptr = allocation.ptr;
    v.cap = allocation.len;
}

pub fn shrinkToLength(comptime T: type, v: *Vec(T)) void {
    return shrinkToLength_(@ptrCast(v), @sizeOf(T));
}
