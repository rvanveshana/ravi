const errors = @import("errors.zig");

pub fn classify(value: i64) errors.TypeId {
    if (value <= -3000) return .function;
    if (value <= -2000) return .string;
    if (value <= -1000) return .dictionary;
    if (value < 0) return .collection;
    return .integer;
}
