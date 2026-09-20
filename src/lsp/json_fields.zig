const std = @import("std");

pub fn appendJsonString(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try list.append(allocator, '"');
    for (value) |byte| switch (byte) {
        '"' => try list.appendSlice(allocator, "\\\""),
        '\\' => try list.appendSlice(allocator, "\\\\"),
        '\n' => try list.appendSlice(allocator, "\\n"),
        '\r' => try list.appendSlice(allocator, "\\r"),
        '\t' => try list.appendSlice(allocator, "\\t"),
        else => if (byte < 0x20) {
            const escaped = try std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{byte});
            defer allocator.free(escaped);
            try list.appendSlice(allocator, escaped);
        } else try list.append(allocator, byte),
    };
    try list.append(allocator, '"');
}

fn field(value: std.json.Value, name: []const u8) ?std.json.Value {
    switch (value) {
        .object => |object| {
            if (object.get(name)) |found| return found;
            var entries = object.iterator();
            while (entries.next()) |entry| if (field(entry.value_ptr.*, name)) |found| return found;
        },
        .array => |array| for (array.items) |item| {
            if (field(item, name)) |found| return found;
        },
        else => {},
    }
    return null;
}
pub fn stringField(value: std.json.Value, name: []const u8) ?[]const u8 {
    return switch (field(value, name) orelse return null) {
        .string => |text| text,
        else => null,
    };
}
pub fn integerField(value: std.json.Value, name: []const u8) ?i64 {
    return switch (field(value, name) orelse return null) {
        .integer => |number| number,
        else => null,
    };
}
