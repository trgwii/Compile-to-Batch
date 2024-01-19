pub fn Result_Ok(comptime T: type, value: T) Result(T) {
    return .{ .x = .{ .val = value }, .ok = true };
}
pub fn Result_Err(comptime T: type, err: [*:0]const u8) Result(T) {
    return .{ .x = .{ .err = err }, .ok = false };
}

pub fn Result(comptime T: type) type {
    return extern struct {
        x: extern union {
            val: T,
            err: [*:0]const u8,
        },
        ok: bool,
        pub fn Ok(val: T) Result(T) {
            return Result_Ok(T, val);
        }
        pub fn Err(err: [*:0]const u8) Result(T) {
            return Result_Err(T, err);
        }
        pub fn fromZig(res: anyerror!T) Result(T) {
            return if (res) |val| Ok(val) else |err| fromZigErr(err);
        }
        pub fn fromZigErr(err: anyerror) Result(T) {
            return Err(@errorName(err));
        }
    };
}
