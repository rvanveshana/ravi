const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");

pub fn sourceLocation(token: lexer.Token) bytecode.SourceLocation {
    return .{ .start_offset = token.start_offset, .end_offset = token.end_offset, .line = token.line, .column = token.column };
}

pub fn comparisonOpcode(text: []const u8) ?bytecode.OpCode {
    if (std.mem.eql(u8, text, "==")) return .equal;
    if (std.mem.eql(u8, text, "!=")) return .not_equal;
    if (std.mem.eql(u8, text, "<")) return .less;
    if (std.mem.eql(u8, text, "<=")) return .less_equal;
    if (std.mem.eql(u8, text, ">")) return .greater;
    if (std.mem.eql(u8, text, ">=")) return .greater_equal;
    return null;
}

pub fn localSlot(names: *std.ArrayListUnmanaged([]const u8), allocator: std.mem.Allocator, name: []const u8) !usize {
    if (findLocal(names.items, name)) |slot| return slot;
    try names.append(allocator, name);
    return names.items.len - 1;
}

pub fn findLocal(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |existing, index| if (std.mem.eql(u8, existing, name)) return index;
    return null;
}

pub fn findCapture(captures: []const []const u8, name: []const u8) ?usize {
    for (captures, 0..) |capture, index| if (std.mem.eql(u8, capture, name)) return index;
    return null;
}
