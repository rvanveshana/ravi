const bytecode = @import("ravi_bytecode");

pub fn operator(text: []const u8) ?bytecode.OpCode {
    if (std.mem.eql(u8, text, "+")) return .add;
    if (std.mem.eql(u8, text, "-")) return .subtract;
    if (std.mem.eql(u8, text, "*")) return .multiply;
    if (std.mem.eql(u8, text, "/")) return .divide;
    if (std.mem.eql(u8, text, "%")) return .modulo;
    if (std.mem.eql(u8, text, "==")) return .equal;
    if (std.mem.eql(u8, text, "!=")) return .not_equal;
    if (std.mem.eql(u8, text, "<")) return .less;
    if (std.mem.eql(u8, text, "<=")) return .less_equal;
    if (std.mem.eql(u8, text, ">")) return .greater;
    if (std.mem.eql(u8, text, ">=")) return .greater_equal;
    return null;
}

pub fn precedence(op: bytecode.OpCode) u8 {
    return switch (op) {
        .logic_or => 1,
        .logic_and => 2,
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => 3,
        .multiply, .divide, .modulo => 5,
        .add, .subtract => 4,
        else => 0,
    };
}

const std = @import("std");

test "expression operator precedence" {
    try std.testing.expectEqual(@as(u8, 5), precedence(.multiply));
    try std.testing.expectEqual(@as(?bytecode.OpCode, .add), operator("+"));
}
