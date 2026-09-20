const std = @import("std");
pub const Method = struct { english: []const u8, kannada: []const u8, opcode: []const u8, arguments: usize, mutates: bool };
pub const methods = [_]Method{
    .{ .english = "lower", .kannada = "chikku", .opcode = "string_lower", .arguments = 0, .mutates = false },
    .{ .english = "upper", .kannada = "doddu", .opcode = "string_upper", .arguments = 0, .mutates = false },
    .{ .english = "strip", .kannada = "kadi", .opcode = "string_strip", .arguments = 0, .mutates = false },
    .{ .english = "find", .kannada = "huduk", .opcode = "string_find", .arguments = 1, .mutates = false },
    .{ .english = "replace", .kannada = "badla", .opcode = "string_replace", .arguments = 2, .mutates = false },
    .{ .english = "split", .kannada = "ode", .opcode = "string_split", .arguments = 1, .mutates = false },
    .{ .english = "join", .kannada = "jote", .opcode = "string_join", .arguments = 1, .mutates = false },
    .{ .english = "length", .kannada = "gatra", .opcode = "length", .arguments = 0, .mutates = false },
    .{ .english = "append", .kannada = "serisu", .opcode = "append_collection", .arguments = 1, .mutates = true },
    .{ .english = "insert", .kannada = "haku", .opcode = "insert_collection", .arguments = 2, .mutates = true },
    .{ .english = "remove", .kannada = "tegi", .opcode = "remove_collection", .arguments = 1, .mutates = true },
    .{ .english = "contains", .kannada = "olagide", .opcode = "contains_collection", .arguments = 1, .mutates = false },
    .{ .english = "clear", .kannada = "khaali", .opcode = "clear_collection", .arguments = 0, .mutates = true },
    .{ .english = "pop", .kannada = "kithu", .opcode = "pop_collection", .arguments = 0, .mutates = false },
    .{ .english = "count", .kannada = "enisu", .opcode = "count_collection", .arguments = 0, .mutates = false },
    .{ .english = "reverse", .kannada = "ultha", .opcode = "reverse_collection", .arguments = 0, .mutates = true },
    .{ .english = "sort", .kannada = "jodisu", .opcode = "sort_collection", .arguments = 0, .mutates = true },
    .{ .english = "get", .kannada = "tago", .opcode = "dict_get", .arguments = 1, .mutates = false },
    .{ .english = "update", .kannada = "badala", .opcode = "dict_put", .arguments = 2, .mutates = true },
    .{ .english = "keys", .kannada = "kili", .opcode = "dict_keys", .arguments = 0, .mutates = false },
    .{ .english = "values", .kannada = "bele", .opcode = "dict_values", .arguments = 0, .mutates = false },
    .{ .english = "items", .kannada = "jodi", .opcode = "dict_items", .arguments = 0, .mutates = false },
    .{ .english = "union", .kannada = "koodu", .opcode = "set_union", .arguments = 1, .mutates = false },
    .{ .english = "intersection", .kannada = "ondu", .opcode = "set_intersection", .arguments = 1, .mutates = false },
    .{ .english = "difference", .kannada = "bere", .opcode = "set_difference", .arguments = 1, .mutates = false },
    .{ .english = "update", .kannada = "badala", .opcode = "constant", .arguments = 2, .mutates = true },
    .{ .english = "pop", .kannada = "kithu", .opcode = "pop_collection", .arguments = 1, .mutates = false },
};
pub fn resolve(name: []const u8, language: anytype, arguments: usize) ?usize {
    for (methods, 0..) |method, index| {
        const spelling = if (language == .kn) method.kannada else method.english;
        if (std.mem.eql(u8, spelling, name) and method.arguments == arguments) return index;
    }
    return null;
}
