const std = @import("std");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
const syntax = @import("ravi_syntax");

test "lossless syntax tree and parser retain trivia and expression shapes" {
    const source = "# comment\nx = [1, 2]\ny = {1: 2}\nx[0]\nx[0:1]\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var tree = try syntax.SyntaxTree.fromTokens(std.testing.allocator, source, tokens);
    defer tree.deinit();
    try std.testing.expect(tree.trivia.items.len >= 5);
    try std.testing.expectEqualStrings("# comment", tree.tokenText(tree.trivia.items[0]));
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var array = false;
    var map = false;
    var index = false;
    var slice = false;
    for (module.expressions.items) |expression| switch (expression.kind) {
        .array => array = true,
        .map => map = true,
        .index => index = true,
        .slice => slice = true,
        else => {},
    };
    try std.testing.expect(array and map and index and slice);
}

test "parser accepts function defaults and variadic parameters" {
    const source = "kriya f(value: int = 1, *values, **options):\n    kodu value\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
}

test "parser accepts none return annotations" {
    const source = "kriya run(limit: int) -> none:\n    munde\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
}

test "parser retains optional class base names" {
    const source = "roopa Child guru Parent:\n    kodu none\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    switch (module.statements.items[0].kind) {
        .class_decl => |class_decl| try std.testing.expectEqualStrings("Parent", class_decl.base.? ),
        else => return error.TestExpectedEqual,
    }
}

test "parser preserves visibility modifiers" {
    const source = "swanta roopa Hidden:\n    saarva kriya open():\n        kodu none\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    switch (module.statements.items[0].kind) {
        .class_decl => |class_decl| try std.testing.expectEqualStrings("private", @tagName(class_decl.visibility)),
        else => return error.TestExpectedEqual,
    }
}
