const std = @import("std");

/// High-performance 64-bit NaN-boxed Value representation for Ravi dynamic & static execution.
/// IEEE 754 Double Precision NaN boxing layout:
/// Sign (1) | Exponent 11 bits (11111111111) | Quiet NaN bit (1) | Tag 3 bits | Payload 48 bits
pub const Value = enum(u64) {
    _,

    const QNAN: u64 = 0x7FF8000000000000;
    const SIGN_BIT: u64 = 0x8000000000000000;

    const TAG_NIL: u64 = 1;
    const TAG_FALSE: u64 = 2;
    const TAG_TRUE: u64 = 3;
    const TAG_INT: u64 = 4;
    const TAG_OBJ: u64 = 5;

    pub inline fn fromFloat(f: f64) Value {
        return @enumFromInt(@as(u64, @bitCast(f)));
    }

    pub inline fn fromInt(i: i64) Value {
        const payload = @as(u64, @bitCast(i)) & 0x0000FFFFFFFFFFFF;
        return @enumFromInt(QNAN | (TAG_INT << 48) | payload);
    }

    pub inline fn fromBool(b: bool) Value {
        const tag = if (b) TAG_TRUE else TAG_FALSE;
        return @enumFromInt(QNAN | (tag << 48));
    }

    pub inline fn nil() Value {
        return @enumFromInt(QNAN | (TAG_NIL << 48));
    }

    pub inline fn fromPtr(ptr: *anyopaque) Value {
        const payload = @intFromPtr(ptr) & 0x0000FFFFFFFFFFFF;
        return @enumFromInt(QNAN | (TAG_OBJ << 48) | payload);
    }

    pub inline fn isFloat(self: Value) bool {
        return (@intFromEnum(self) & QNAN) != QNAN;
    }

    pub inline fn isInt(self: Value) bool {
        return (@intFromEnum(self) & (QNAN | (0x7 << 48))) == (QNAN | (TAG_INT << 48));
    }

    pub inline fn isBool(self: Value) bool {
        const tag = (@intFromEnum(self) >> 48) & 0x7;
        return (@intFromEnum(self) & QNAN) == QNAN and (tag == TAG_FALSE or tag == TAG_TRUE);
    }

    pub inline fn isNil(self: Value) bool {
        return @intFromEnum(self) == (QNAN | (TAG_NIL << 48));
    }

    pub inline fn asFloat(self: Value) f64 {
        return @bitCast(@intFromEnum(self));
    }

    pub inline fn asInt(self: Value) i64 {
        const raw = @intFromEnum(self) & 0x0000FFFFFFFFFFFF;
        // Sign-extend 48-bit to 64-bit integer
        if ((raw & 0x0008000000000000) != 0) {
            return @as(i64, @bitCast(raw | 0xFFFF000000000000));
        }
        return @as(i64, @bitCast(raw));
    }

    pub inline fn asBool(self: Value) bool {
        return (@intFromEnum(self) & (0x7 << 48)) == (TAG_TRUE << 48);
    }

    pub inline fn asPtr(self: Value, comptime T: type) *T {
        const raw = @intFromEnum(self) & 0x0000FFFFFFFFFFFF;
        return @ptrFromInt(raw);
    }
};
