const std = @import("std");

export fn panic(msg: [*:0]const u8) noreturn {
	@panic(std.mem.span(msg));
}