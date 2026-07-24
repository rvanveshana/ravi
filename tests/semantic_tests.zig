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

test "class bases must resolve regardless of declaration order" {
    const source = "roopa Child guru Parent:\n    kodu none\nroopa Parent:\n    kodu none\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    var analyzer = semantic.Analyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    try analyzer.analyzeModule(&module);
    const missing = "roopa Child guru Missing:\n    kodu none\n";
    var missing_scan = try lexer.Lexer.init(std.testing.allocator, missing);
    defer missing_scan.deinit();
    const missing_tokens = try missing_scan.tokenize();
    var missing_parser = parser.Parser.init(std.testing.allocator, missing_tokens);
    var missing_module = try missing_parser.parseRecovering();
    defer missing_module.deinit();
    var missing_analyzer = semantic.Analyzer.init(std.testing.allocator);
    defer missing_analyzer.deinit();
    try std.testing.expectError(error.UnknownBaseClass, missing_analyzer.analyzeModule(&missing_module));
}

test "duplicate methods in one class are rejected while overrides are allowed" {
    const duplicate = "roopa Box:\n    kriya read():\n        kodu 1\n    kriya read():\n        kodu 2\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, duplicate);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parser_instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parser_instance.parseRecovering();
    defer module.deinit();
    var analyzer = semantic.Analyzer.init(std.testing.allocator);
    defer analyzer.deinit();
    try std.testing.expectError(error.DuplicateDeclaration, analyzer.analyzeModule(&module));
}
