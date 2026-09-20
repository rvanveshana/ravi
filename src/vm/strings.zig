const std = @import("std");

pub fn width(first: u8) ?usize {
    return if (first < 0x80) 1 else if (first & 0xE0 == 0xC0) 2 else if (first & 0xF0 == 0xE0) 3 else if (first & 0xF8 == 0xF0) 4 else null;
}
fn codepoint(text: []const u8, start: usize) ?struct { value: i64, width: usize } {
    if (start >= text.len) return null;
    const byte_width = width(text[start]) orelse return null;
    if (start + byte_width > text.len) return null;
    const value = std.unicode.utf8Decode(text[start .. start + byte_width]) catch return null;
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
    if (current != ordinal) return null;
    if (cursor < text.len and codepoint(text, cursor) == null) return null;
    return cursor;
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

test "Kannada combining marks and non-BMP scalars preserve UTF-8 offsets" {
    const kannada = "\u{0C95}\u{0CBF}";
    try std.testing.expectEqual(@as(usize, 2), length(kannada));
    try std.testing.expectEqual(@as(?i64, 0x0C95), at(kannada, 0));
    try std.testing.expectEqual(@as(?i64, 0x0CBF), at(kannada, 1));
    try std.testing.expectEqual(@as(?usize, 3), offset(kannada, 1));
    try std.testing.expectEqual(@as(?usize, 6), offset(kannada, 2));
    try std.testing.expectEqual(@as(?i64, 0x1F600), at("\u{1F600}", 0));
}
