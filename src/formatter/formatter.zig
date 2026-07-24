const std = @import("std");

/// Conservative canonical formatter. It preserves syntax and comments while
/// normalizing line endings, trailing whitespace, leading tabs, and the final
/// newline. Syntax-aware spacing can build on the same lossless token tree.
pub fn format(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < source.len) {
        const line_start = cursor;
        while (cursor < source.len and source[cursor] != '\n' and source[cursor] != '\r') cursor += 1;
        var line_end = cursor;
        while (line_end > line_start and (source[line_end - 1] == ' ' or source[line_end - 1] == '\t')) line_end -= 1;
        var content = line_start;
        while (content < line_end and (source[content] == ' ' or source[content] == '\t')) : (content += 1) {
            if (source[content] == '\t') {
                try output.appendSlice(allocator, "    ");
            } else {
                try output.append(allocator, ' ');
            }
        }
        try output.appendSlice(allocator, source[content..line_end]);
        try output.append(allocator, '\n');
        if (cursor < source.len and source[cursor] == '\r') cursor += 1;
        if (cursor < source.len and source[cursor] == '\n') cursor += 1;
    }
    if (source.len == 0) return output.toOwnedSlice(allocator);
    return output.toOwnedSlice(allocator);
}

test "formatter normalizes whitespace without changing content" {
    const formatted = try format(std.testing.allocator, "kriya main():  \r\n\tkodu 1\t\r\n");
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("kriya main():\n    kodu 1\n", formatted);
}
