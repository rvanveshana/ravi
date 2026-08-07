const std = @import("std");
const lexer = @import("ravi_lexer");
const config = @import("ravi_config");

test "language profiles and mixed keywords" {
    try std.testing.expectEqual(config.SourceLanguage.en, (try config.languageFromHeader("# ravi: language=en\nfunction x():\n")).?);
    try std.testing.expect((try config.languageFromHeader("function x():\n")) == null);
    var english = try lexer.Lexer.initWithLanguage(std.testing.allocator, "function value():\n    return 1\n", .en);
    defer english.deinit();
    const tokens = try english.tokenize();
    try std.testing.expectEqual(lexer.TokenKind.keyword, tokens[0].kind);
    try std.testing.expectEqualStrings("function", config.keywordCanonicalFor(.en, tokens[0].lexeme).?);
    var mixed = try lexer.Lexer.initWithLanguage(std.testing.allocator, "function kriya\n", .en);
    defer mixed.deinit();
    try std.testing.expectError(error.MixedLanguageKeyword, mixed.tokenize());
}

test "keyword canonical matching is restricted to the active language" {
    try std.testing.expect(config.keywordIsCanonical(.en, "function", "function"));
    try std.testing.expect(!config.keywordIsCanonical(.en, "kriya", "function"));
    try std.testing.expect(config.keywordIsCanonical(.kn, "kriya", "function"));
    try std.testing.expect(!config.keywordIsCanonical(.kn, "function", "function"));
}

test "keyword spellings remain valid member names" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "object.tago(1)\nobject.if()\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var saw_tago = false;
    for (tokens) |token| if (std.mem.eql(u8, token.lexeme, "tago")) {
        saw_tago = true;
        try std.testing.expectEqual(lexer.TokenKind.identifier, token.kind);
    };
    try std.testing.expect(saw_tago);
}

test "lexer preserves comments and collection punctuation" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "# comment\nx = [1, 2]\ny = {1: 2}\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var comments: usize = 0;
    var punctuation: usize = 0;
    for (tokens) |token| {
        if (token.kind == .comment) comments += 1;
        if (token.kind == .l_bracket or token.kind == .r_bracket or token.kind == .l_brace or token.kind == .r_brace) punctuation += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), comments);
    try std.testing.expectEqual(@as(usize, 4), punctuation);
}

test "lexer rejects numeric literals with multiple decimal points" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = 1.2.3\n");
    defer scan.deinit();
    try std.testing.expectError(error.InvalidNumber, scan.tokenize());
}

test "lexer keeps raw string prefixes attached to string tokens" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "path = r'C:\\data\\input.rk'\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    try std.testing.expectEqual(lexer.TokenKind.string, tokens[2].kind);
    try std.testing.expectEqualStrings("r'C:\\data\\input.rk'", tokens[2].lexeme);
}

test "lexer keeps formatted string prefixes attached to string tokens" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "message = f\"Result: {value}\"\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    try std.testing.expectEqual(lexer.TokenKind.string, tokens[2].kind);
    try std.testing.expectEqualStrings("f\"Result: {value}\"", tokens[2].lexeme);
}

test "lexer keeps standalone f identifiers unchanged" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "f = 1\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    try std.testing.expectEqual(lexer.TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("f", tokens[0].lexeme);
}

test "all material tokens carry byte and line spans" {
    const source = "value = 42\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    try std.testing.expectEqual(@as(usize, 0), tokens[0].start_offset);
    try std.testing.expectEqual(@as(usize, 5), tokens[0].end_offset);
    try std.testing.expectEqual(@as(usize, 1), tokens[0].line);
    try std.testing.expectEqual(@as(usize, 1), tokens[0].column);
    try std.testing.expectEqualStrings("42", source[tokens[2].start_offset..tokens[2].end_offset]);
}
