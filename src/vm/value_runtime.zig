const errors = @import("errors.zig");
const Value = @import("ravi_vm_value").Value;

pub fn integer(value: i64) errors.RuntimeError!Value {
    return Value.tryFromInt(value) catch return error.IntegerOutOfRange;
}
pub fn makeHandle(kind: Value.ObjectKind, index: usize) errors.RuntimeError!Value {
    return Value.fromHandle(kind, index) catch return error.InvalidInstruction;
}
pub fn requireInteger(value: Value) errors.RuntimeError!i64 {
    if (!value.isInt()) return error.TypeGuardFailed;
    return value.asInt();
}
pub fn arraySlot(value: Value) ?usize {
    const kind = value.handleKind() orelse return null;
    if (kind != .array and kind != .tuple and kind != .set) return null;
    return value.handleIndex();
}
pub fn dictSlot(value: Value) ?usize {
    if (value.handleKind() != .dictionary) return null;
    return value.handleIndex();
}
pub fn instanceSlot(value: Value) ?usize {
    if (value.handleKind() != .instance) return null;
    return value.handleIndex();
}
pub fn toLegacy(value: Value) i64 {
    if (value.isInt()) return value.asInt();
    if (value.isBool()) return @intFromBool(value.asBool());
    if (value.isNil()) return 0;
    return @bitCast(@intFromEnum(value));
}
