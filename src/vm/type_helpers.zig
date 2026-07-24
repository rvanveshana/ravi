const errors = @import("errors.zig");
const Value = @import("ravi_vm_value").Value;

pub fn classify(value: Value) errors.TypeId {
    if (value.handleKind()) |kind| return switch (kind) {
        .string => .string,
        .array, .tuple, .set => .collection,
        .dictionary => .dictionary,
        .function, .closure => .function,
        .instance => .instance,
        else => .integer,
    };
    return .integer;
}
