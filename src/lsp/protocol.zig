const std = @import("std");

pub const max_message_bytes = 16 * 1024 * 1024;
pub const Frame = struct { body: []const u8, consumed: usize };
pub const DecodeError = error{ Incomplete, InvalidHeader, DuplicateLength, MessageTooLarge };

/// Parses one Language Server Protocol frame without allocating. Callers keep
/// incomplete bytes and retry when more stdio/socket data arrives.
pub fn decode(bytes: []const u8) DecodeError!Frame {
    const header_end = std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse return error.Incomplete;
    var length: ?usize = null;
    var lines = std.mem.splitSequence(u8, bytes[0..header_end], "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidHeader;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (!std.ascii.eqlIgnoreCase(name, "Content-Length")) continue;
        if (length != null) return error.DuplicateLength;
        length = std.fmt.parseInt(usize, value, 10) catch return error.InvalidHeader;
    }
    const body_len = length orelse return error.InvalidHeader;
    if (body_len > max_message_bytes) return error.MessageTooLarge;
    const body_start = header_end + 4;
    const frame_end = std.math.add(usize, body_start, body_len) catch return error.MessageTooLarge;
    if (bytes.len < frame_end) return error.Incomplete;
    return .{ .body = bytes[body_start..frame_end], .consumed = frame_end };
}

pub fn encode(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    if (json.len > max_message_bytes) return error.MessageTooLarge;
    return std.fmt.allocPrint(allocator, "Content-Length: {d}\r\n\r\n{s}", .{ json.len, json });
}

test "LSP transport frames messages and preserves following bytes" {
    const first = try encode(std.testing.allocator, "{\"jsonrpc\":\"2.0\"}");
    defer std.testing.allocator.free(first);
    var stream: std.ArrayListUnmanaged(u8) = .empty;
    defer stream.deinit(std.testing.allocator);
    try stream.appendSlice(std.testing.allocator, first);
    try stream.appendSlice(std.testing.allocator, "next");
    const frame = try decode(stream.items);
    try std.testing.expectEqualStrings("{\"jsonrpc\":\"2.0\"}", frame.body);
    try std.testing.expectEqualStrings("next", stream.items[frame.consumed..]);
    try std.testing.expectError(error.Incomplete, decode(first[0 .. first.len - 1]));
}

test "LSP transport rejects duplicate and oversized lengths" {
    try std.testing.expectError(error.DuplicateLength, decode("Content-Length: 0\r\nContent-Length: 0\r\n\r\n"));
    try std.testing.expectError(error.MessageTooLarge, decode("Content-Length: 999999999\r\n\r\n"));
}
