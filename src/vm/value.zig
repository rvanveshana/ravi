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
    const TAG_HANDLE: u64 = 6;
    const HANDLE_INDEX_MASK: u64 = (@as(u64, 1) << 40) - 1;
    pub const ObjectKind = enum(u8) { string, array, tuple, set, dictionary, function, closure, cell, instance, future, channel };
    pub const min_int: i64 = -(@as(i64, 1) << 47);
    pub const max_int: i64 = (@as(i64, 1) << 47) - 1;

    pub inline fn fromFloat(f: f64) Value {
        if (std.math.isNan(f)) return @enumFromInt(QNAN);
        return @enumFromInt(@as(u64, @bitCast(f)));
    }

    pub inline fn fromInt(i: i64) Value {
        std.debug.assert(i >= min_int and i <= max_int);
        const payload = @as(u64, @bitCast(i)) & 0x0000FFFFFFFFFFFF;
        return @enumFromInt(QNAN | (TAG_INT << 48) | payload);
    }

    pub fn tryFromInt(i: i64) error{IntegerOutOfRange}!Value {
        if (i < min_int or i > max_int) return error.IntegerOutOfRange;
        return fromInt(i);
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

    pub fn fromHandle(kind: ObjectKind, index: usize) error{HandleOutOfRange}!Value {
        if (index > HANDLE_INDEX_MASK) return error.HandleOutOfRange;
        const payload = (@as(u64, @intFromEnum(kind)) << 40) | @as(u64, @intCast(index));
        return @enumFromInt(QNAN | (TAG_HANDLE << 48) | payload);
    }

    pub inline fn isFloat(self: Value) bool {
        const bits = @intFromEnum(self);
        return (bits & QNAN) != QNAN or ((bits >> 48) & 0x7) == 0;
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

    pub inline fn isObject(self: Value) bool {
        return tagBits(self) == TAG_OBJ;
    }

    pub inline fn isHandle(self: Value) bool {
        return tagBits(self) == TAG_HANDLE;
    }

    pub fn handleKind(self: Value) ?ObjectKind {
        if (!self.isHandle()) return null;
        const raw: u8 = @truncate((@intFromEnum(self) >> 40) & 0xff);
        if (raw >= @typeInfo(ObjectKind).@"enum".field_names.len) return null;
        return @enumFromInt(raw);
    }

    pub fn handleIndex(self: Value) ?usize {
        if (!self.isHandle()) return null;
        return @intCast(@intFromEnum(self) & HANDLE_INDEX_MASK);
    }

    pub fn truthy(self: Value) bool {
        if (self.isNil()) return false;
        if (self.isBool()) return self.asBool();
        if (self.isInt()) return self.asInt() != 0;
        if (self.isFloat()) return self.asFloat() != 0.0;
        return true;
    }

    pub fn eql(left: Value, right: Value) bool {
        if (left.isFloat() and right.isFloat()) return left.asFloat() == right.asFloat();
        if ((left.isInt() and right.isFloat()) or (left.isFloat() and right.isInt())) {
            const left_number = if (left.isFloat()) left.asFloat() else @as(f64, @floatFromInt(left.asInt()));
            const right_number = if (right.isFloat()) right.asFloat() else @as(f64, @floatFromInt(right.asInt()));
            return left_number == right_number;
        }
        return @intFromEnum(left) == @intFromEnum(right);
    }

    pub fn hash(self: Value) u64 {
        var bits = @intFromEnum(self);
        if (self.isFloat()) {
            const number = self.asFloat();
            if (number == 0.0) {
                bits = 0;
            } else if (std.math.isFinite(number)) {
                const min_number = @as(f64, @floatFromInt(min_int));
                const max_number = @as(f64, @floatFromInt(max_int));
                if (number >= min_number and number <= max_number) {
                    const integer = @as(i64, @intFromFloat(number));
                    if (@as(f64, @floatFromInt(integer)) == number) bits = @intFromEnum(Value.fromInt(integer));
                }
            }
        } else if (self.isInt()) {
            bits = @intFromEnum(Value.fromInt(self.asInt()));
        }
        bits ^= bits >> 30;
        bits *%= 0xbf58476d1ce4e5b9;
        bits ^= bits >> 27;
        bits *%= 0x94d049bb133111eb;
        return bits ^ (bits >> 31);
    }

    pub inline fn asFloat(self: Value) f64 {
        return @bitCast(@intFromEnum(self));
    }

    pub inline fn asInt(self: Value) i64 {
        const raw = @intFromEnum(self) & 0x0000FFFFFFFFFFFF;
        // Sign-extend 48-bit to 64-bit integer
        if ((raw & 0x0000800000000000) != 0) {
            return @as(i64, @bitCast(raw | 0xFFFF000000000000));
        }
        return @as(i64, @bitCast(raw));
    }

    pub inline fn asBool(self: Value) bool {
        return (@intFromEnum(self) & (0x7 << 48)) == (TAG_TRUE << 48);
    }

    pub inline fn asPtr(self: Value, comptime T: type) *T {
        const payload = @intFromEnum(self) & 0x0000FFFFFFFFFFFF;
        const canonical = if ((payload & 0x0000800000000000) != 0) payload | 0xFFFF000000000000 else payload;
        return @ptrFromInt(canonical);
    }

    inline fn tagBits(self: Value) u64 {
        if ((@intFromEnum(self) & QNAN) != QNAN) return 0;
        return (@intFromEnum(self) >> 48) & 0x7;
    }
};

test "NaN-boxed values round trip scalar payloads" {
    try std.testing.expectEqual(@as(i64, 42), Value.fromInt(42).asInt());
    try std.testing.expectEqual(@as(i64, -42), Value.fromInt(-42).asInt());
    try std.testing.expect(Value.fromBool(true).asBool());
    try std.testing.expect(Value.nil().isNil());
    try std.testing.expectEqual(@as(f64, 1.5), Value.fromFloat(1.5).asFloat());
    try std.testing.expect(Value.fromFloat(std.math.nan(f64)).isFloat());
    try std.testing.expectError(error.IntegerOutOfRange, Value.tryFromInt(Value.max_int + 1));
}

test "typed handles cannot collide across runtime object kinds" {
    const array = try Value.fromHandle(.array, 42);
    const string = try Value.fromHandle(.string, 42);
    try std.testing.expect(array.isHandle());
    try std.testing.expectEqual(Value.ObjectKind.array, array.handleKind().?);
    try std.testing.expectEqual(@as(usize, 42), array.handleIndex().?);
    try std.testing.expect(!Value.eql(array, string));
    try std.testing.expectError(error.HandleOutOfRange, Value.fromHandle(.array, (@as(usize, 1) << 40)));
}

test "value equality hashing and truthiness have stable edge semantics" {
    try std.testing.expect(Value.eql(Value.fromFloat(-0.0), Value.fromFloat(0.0)));
    try std.testing.expectEqual(Value.fromFloat(-0.0).hash(), Value.fromFloat(0.0).hash());
    try std.testing.expect(Value.eql(Value.fromInt(3), Value.fromFloat(3.0)));
    try std.testing.expectEqual(Value.fromInt(3).hash(), Value.fromFloat(3.0).hash());
    try std.testing.expect(!Value.eql(Value.fromFloat(std.math.nan(f64)), Value.fromFloat(std.math.nan(f64))));
    try std.testing.expect(!Value.nil().truthy());
    try std.testing.expect(!Value.fromInt(0).truthy());
    try std.testing.expect(Value.fromInt(1).truthy());
}
