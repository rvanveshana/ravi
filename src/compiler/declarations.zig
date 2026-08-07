const std = @import("std");
const lexer = @import("ravi_lexer");
const helpers = @import("helpers.zig");

pub fn collectClasses(comptime Error: type, self: anytype, tokens: []const lexer.Token) Error!void {
    var index: usize = 0;
    while (index + 1 < tokens.len) : (index += 1) {
        if (tokens[index].kind != .keyword or !self.keyword(tokens[index], "class") or tokens[index + 1].kind != .identifier) continue;
        if (self.class_count == self.class_names.len) return error.InvalidFunction;
        var header_end = index + 2;
        while (header_end < tokens.len and tokens[header_end].kind != .newline and tokens[header_end].kind != .eof) header_end += 1;
        var body_first = header_end + 1;
        if (body_first < tokens.len and tokens[body_first].kind == .indent) body_first += 1;
        const body_after = helpers.skipSuite(tokens, header_end + 1);
        self.class_names[self.class_count] = tokens[index + 1].lexeme;
        self.class_bases[self.class_count] = null;
        var header_cursor = index + 2;
        while (header_cursor < header_end) : (header_cursor += 1) {
            if (self.keyword(tokens[header_cursor], "guru") and header_cursor + 1 < header_end and tokens[header_cursor + 1].kind == .identifier) {
                self.class_bases[self.class_count] = tokens[header_cursor + 1].lexeme;
                break;
            }
        }
        self.class_body_first[self.class_count] = body_first;
        self.class_body_end[self.class_count] = if (body_after > 0) body_after - 1 else body_first;
        self.class_count += 1;
    }
}
