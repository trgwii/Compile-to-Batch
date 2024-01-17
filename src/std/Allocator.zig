pub const Allocator = extern struct {
	realloc: ?*anyopaque,
	state: ?*anyopaque,
};
