const std = @import("std");

pub const Kind = enum { dynamic, none, boolean, integer, float, string, function, never, unknown };
pub const Type = struct { kind: Kind, name: []const u8 };
pub const TypeId = u32;
pub const Guard = enum { none, check_integer, check_float, check_boolean, check_string, box_dynamic };

pub fn fromName(name: []const u8) Type {
    const kind: Kind = if (std.mem.eql(u8, name, "int")) .integer else if (std.mem.eql(u8, name, "float")) .float else if (std.mem.eql(u8, name, "bool")) .boolean else if (std.mem.eql(u8, name, "str")) .string else if (std.mem.eql(u8, name, "none")) .none else if (std.mem.eql(u8, name, "dinamika")) .dynamic else if (std.mem.eql(u8, name, "never")) .never else .unknown;
    return .{ .kind = kind, .name = name };
}

pub fn isValid(t: Type) bool {
    return t.kind != .unknown;
}
pub fn consistent(actual: Type, expected: Type) bool {
    return actual.kind == expected.kind or actual.kind == .dynamic or expected.kind == .dynamic;
}
pub fn guardFor(actual: Type, expected: Type) Guard {
    if (actual.kind == .dynamic and expected.kind != .dynamic) return switch (expected.kind) {
        .integer => .check_integer,
        .float => .check_float,
        .boolean => .check_boolean,
        .string => .check_string,
        else => .none,
    };
    if (expected.kind == .dynamic and actual.kind != .dynamic) return .box_dynamic;
    return .none;
}
