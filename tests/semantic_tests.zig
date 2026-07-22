const std = @import("std");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
const semantic = @import("ravi_semantic");

test "typed arrays accept homogeneous values" {
    const source = "values: int[] = [1, 2, 3]\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    var analyzer = semantic.Analyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    try analyzer.analyzeModule(&module);
}

test "typed arrays reject mixed element types" {
    const source = "values: int[] = [1, 2.5]\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    var analyzer = semantic.Analyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    try std.testing.expectError(error.TypeMismatch, analyzer.analyzeModule(&module));
}
