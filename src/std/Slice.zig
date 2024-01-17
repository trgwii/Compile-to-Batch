pub fn Slice(comptime T: type) type {
	return extern struct {
		ptr: [*]T,
		len: usize,
	};
}
