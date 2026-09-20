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
            const escaped = try std.fmt.allocPrint(allocator, "\\u{d:0>4}", .{byte});
            defer allocator.free(escaped);
            try list.appendSlice(allocator, escaped);
        } else try list.append(allocator, byte),
    };
    try list.append(allocator, '"');
}

pub fn stringField(body: []const u8, field: []const u8) ?[]const u8 {
    var key: [96]u8 = undefined;
    const prefix = std.fmt.bufPrint(&key, "\"{s}\":\"", .{field}) catch return null;
    const start = (std.mem.indexOf(u8, body, prefix) orelse return null) + prefix.len;
    const end = std.mem.indexOfScalarPos(u8, body, start, '"') orelse return null;
    return body[start..end];
}

pub fn integerField(body: []const u8, field: []const u8) ?i64 {
    var key: [96]u8 = undefined;
    const prefix = std.fmt.bufPrint(&key, "\"{s}\":", .{field}) catch return null;
    const start = (std.mem.indexOf(u8, body, prefix) orelse return null) + prefix.len;
    var end = start;
    while (end < body.len and (std.ascii.isDigit(body[end]) or body[end] == '-')) : (end += 1) {}
    return std.fmt.parseInt(i64, body[start..end], 10) catch null;
}
