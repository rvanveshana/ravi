const std = @import("std");

pub fn width(first: u8) ?usize {
    return if (first < 0x80) 1 else if (first & 0xE0 == 0xC0) 2 else if (first & 0xF0 == 0xE0) 3 else if (first & 0xF8 == 0xF0) 4 else null;
}
fn codepoint(text: []const u8, start: usize) ?struct { value: i64, width: usize } {
    if (start >= text.len) return null;
    const byte_width = width(text[start]) orelse return null;
    if (start + byte_width > text.len) return null;
    var value: i64 = if (byte_width == 1) text[start] else @intCast(text[start] & (@as(u8, 0x7F) >> @intCast(byte_width - 2)));
    for (1..byte_width) |index| {
        const continuation = text[start + index];
        if (continuation & 0xC0 != 0x80) return null;
        value = (value << 6) | @as(i64, continuation & 0x3F);
    }
    const minimum: i64 = switch (byte_width) { 1 => 0, 2 => 0x80, 3 => 0x800, 4 => 0x10000, else => unreachable };
    if (value < minimum or value > 0x10FFFF or (value >= 0xD800 and value <= 0xDFFF)) return null;
    return .{ .value = value, .width = byte_width };
}
pub fn length(text: []const u8) usize {
    var cursor: usize = 0;
    var count: usize = 0;
    while (cursor < text.len) : (count += 1) cursor += (codepoint(text, cursor) orelse return count).width;
    return count;
}
pub fn offset(text: []const u8, ordinal: usize) ?usize {
    var cursor: usize = 0;
    var current: usize = 0;
    while (cursor < text.len and current < ordinal) : (current += 1) cursor += (codepoint(text, cursor) orelse return null).width;
    return if (current == ordinal) cursor else null;
}
pub fn at(text: []const u8, ordinal: usize) ?i64 {
    const start = offset(text, ordinal) orelse return null;
    if (start >= text.len) return null;
    return (codepoint(text, start) orelse return null).value;
}
test "UTF-8 string helpers" {
    try std.testing.expectEqual(@as(usize, 3), length("AÀB"));
    try std.testing.expectEqual(@as(?i64, 0xC0), at("AÀB", 1));
}

test "UTF-8 helpers reject malformed, overlong, and surrogate sequences" {
    try std.testing.expectEqual(@as(usize, 0), length("\xC0\x80"));
    try std.testing.expect(at("\xED\xA0\x80", 0) == null);
    try std.testing.expect(offset("\xF4\x90\x80\x80", 0) == null);
}
