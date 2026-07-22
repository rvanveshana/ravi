const std = @import("std");
const lexer = @import("ravi_lexer");

/// Lossless source representation. Tokens retain their source slices, so
/// comments, whitespace boundaries, newlines, and malformed regions can be
/// reconstructed without reparsing the source.
pub const SyntaxTree = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: std.ArrayListUnmanaged(lexer.Token) = .empty,
    trivia: std.ArrayListUnmanaged(usize) = .empty,

    pub fn fromTokens(allocator: std.mem.Allocator, source: []const u8, tokens: []const lexer.Token) !SyntaxTree {
        var tree = SyntaxTree{ .allocator = allocator, .source = source };
        errdefer tree.deinit();
        try tree.tokens.appendSlice(allocator, tokens);
        for (tokens, 0..) |token, index| if (token.kind == .comment or token.kind == .newline or token.kind == .indent or token.kind == .dedent) try tree.trivia.append(allocator, index);
        return tree;
    }
    pub fn deinit(self: *SyntaxTree) void {
        self.tokens.deinit(self.allocator);
        self.trivia.deinit(self.allocator);
    }
    pub fn tokenText(self: *const SyntaxTree, index: usize) []const u8 {
        return self.tokens.items[index].lexeme;
    }
};
