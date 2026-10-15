const std = @import("std");

/// Conservative canonical formatter. It preserves syntax and comments while
/// normalizing line endings, trailing whitespace, leading tabs, and the final
/// newline. Syntax-aware spacing can build on the same lossless token tree.
pub fn format(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const literal = try literalBytes(allocator, source);
    defer allocator.free(literal);
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < source.len) {
        const line_start = cursor;
        while (cursor < source.len and source[cursor] != '\n' and source[cursor] != '\r') cursor += 1;
        var line_end = cursor;
        while (line_end > line_start and !literal[line_end - 1] and (source[line_end - 1] == ' ' or source[line_end - 1] == '\t')) line_end -= 1;
        var content = line_start;
        while (content < line_end and (source[content] == ' ' or source[content] == '\t')) : (content += 1) {
            if (source[content] == '\t' and !literal[content]) {
                try output.appendSlice(allocator, "    ");
            } else {
                try output.append(allocator, source[content]);
            }
        }
        try output.appendSlice(allocator, source[content..line_end]);
        if (cursor < source.len and literal[cursor]) {
            try output.append(allocator, source[cursor]);
            if (source[cursor] == '\r' and cursor + 1 < source.len and source[cursor + 1] == '\n') try output.append(allocator, '\n');
        } else try output.append(allocator, '\n');
        if (cursor < source.len and source[cursor] == '\r') cursor += 1;
        if (cursor < source.len and source[cursor] == '\n') cursor += 1;
    }
    if (source.len == 0) return output.toOwnedSlice(allocator);
    return output.toOwnedSlice(allocator);
}

fn literalBytes(allocator: std.mem.Allocator, source: []const u8) ![]bool {
    const mask = try allocator.alloc(bool, source.len);
    @memset(mask, false);
    var index: usize = 0;
    while (index < source.len) {
        if (source[index] == '#') {
            while (index < source.len and source[index] != '\n') index += 1;
        } else if (source[index] == '\'' or source[index] == '"') {
            const start = index;
            const quote = source[index];
            const triple = index + 2 < source.len and source[index + 1] == quote and source[index + 2] == quote;
            const width: usize = if (triple) 3 else 1;
            index += width;
            while (index < source.len) {
                if (source[index] == '\\') {
                    index = @min(index + 2, source.len);
                } else if (source[index] == quote and (!triple or (index + 2 < source.len and source[index + 1] == quote and source[index + 2] == quote))) {
                    index += width;
                    break;
                } else index += 1;
            }
            @memset(mask[start..index], true);
        } else index += 1;
    }
    return mask;
}

test "formatter preserves literal bytes including CRLF tabs and trailing spaces" {
    const source = "x = \"\"\"first  \r\n\tsecond\t \r\n\"\"\"  \r\n";
    const formatted = try format(std.testing.allocator, source);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("x = \"\"\"first  \r\n\tsecond\t \r\n\"\"\"\n", formatted);
    const twice = try format(std.testing.allocator, formatted);
    defer std.testing.allocator.free(twice);
    try std.testing.expectEqualStrings(formatted, twice);
}

test "formatter normalizes whitespace without changing content" {
    const formatted = try format(std.testing.allocator, "kriya main():  \r\n\tkodu 1\t\r\n");
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("kriya main():\n    kodu 1\n", formatted);
}
