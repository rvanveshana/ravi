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
    const function = module.statements.items[0].kind.function;
    try std.testing.expectEqual(@as(usize, 3), function.params_count);
    try std.testing.expectEqual(.positional, module.parameters.items[function.params_first].kind);
    try std.testing.expectEqual(.variadic, module.parameters.items[function.params_first + 1].kind);
    try std.testing.expectEqual(.keyword_variadic, module.parameters.items[function.params_first + 2].kind);
}

test "parser preserves yield as a distinct statement" {
    const source = "kriya values():\n    taru 1\n    kodu 2\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(module.statements.items.len >= 3);
    const body = module.statements.items[0].kind.function;
    try std.testing.expect(module.statements.items[body.body_first].kind == .yield_stmt);
}

test "parser preserves member assignment targets" {
    const source = "box.value = 42\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(module.statements.items[0].kind == .expression);
    const expression_id = module.statements.items[0].kind.expression;
    switch (module.expressions.items[expression_id].kind) {
        .assignment => |assignment| {
            try std.testing.expect(assignment.target != null);
            const target = module.expressions.items[assignment.target.?].kind;
            try std.testing.expect(target == .member);
        },
        else => return error.TestUnexpectedResult,
    }
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

test "parser keeps brace formatted strings distinct from plain strings" {
    const source = "message = f\"Result: {value}\"\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var found = false;
    for (module.expressions.items) |expression| switch (expression.kind) {
        .formatted_string => |value| {
            found = true;
            try std.testing.expectEqualStrings("f\"Result: {value}\"", value.template);
            try std.testing.expectEqual(@as(usize, 1), value.arg_count);
        },
        else => {},
    };
    try std.testing.expect(found);
}

test "parser accepts normal expressions inside formatted strings" {
    const source = "message = f\"Result: {value + 1}\"\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 1), module.format_args.items.len);
    const argument = module.expressions.items[module.format_args.items[0]];
    try std.testing.expect(argument.kind == .binary);
}

test "formatted placeholders use the active language profile" {
    const source = "message = f\"Result: {not value}\"\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .en);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .en);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 1), module.format_args.items.len);
    try std.testing.expect(module.expressions.items[module.format_args.items[0]].kind == .unary);
}

test "parser keeps nested delimiters inside formatted expressions" {
    const source = "message = f\"Value: {items[index]}\"\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 1), module.format_args.items.len);
    try std.testing.expect(module.expressions.items[module.format_args.items[0]].kind == .index);
}

test "parser retains context manager binding and suite" {
    const source = "file_open('data.txt') jote file aagi:\n    text = file.read()\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    switch (module.statements.items[module.statements.items.len - 1].kind) {
        .context => |context| {
            try std.testing.expectEqualStrings("file", context.binding.?);
            try std.testing.expectEqual(@as(usize, 1), context.body_count);
        },
        else => return error.TestExpectedEqual,
    }
}

test "parser rejects context binding without aagi" {
    const source = "file_open('data.txt') jote file:\n    kodu none\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expect(module.diagnostics.items.len != 0);
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
        .class_decl => |class_decl| try std.testing.expectEqualStrings("Parent", class_decl.base.?),
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

test "parser keeps elif suites separate from following top-level statements" {
    const source = "adre 0:\n    kodu 1\ninadre 1:\n    kodu 2\nilla:\n    kodu 3\nmudrisu(4)\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 6), module.statements.items.len);
    switch (module.statements.items[0].kind) {
        .control => |control| {
            try std.testing.expectEqual(@as(usize, 1), control.body_first);
            try std.testing.expectEqual(@as(usize, 1), control.body_count);
            try std.testing.expectEqual(@as(usize, 2), control.else_first);
            try std.testing.expectEqual(@as(usize, 3), control.else_count);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parser keeps conditional example top-level statements reachable" {
    const source = "x = 4\nadre x > 5:\n    mudrisu(0)\ninadre x == 4:\n    mudrisu(2)\nilla:\n    mudrisu(1)\nadre x > 2 mattu x < 10:\n    mudrisu(10)\nadre x == 4 athva x == 5:\n    mudrisu(20)\nmudrisu(4 alli [1, 4, 6])\nmudrisu(none ide none)\nadre x >= 4:\n    adre x <= 4:\n        mudrisu(30)\n    illa:\n        mudrisu(0)\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var instance = parser.Parser.init(std.testing.allocator, tokens);
    var module = try instance.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(module.statements.items.len > 8);
    switch (module.statements.items[1].kind) {
        .control => |control| {
            try std.testing.expect(control.else_first + control.else_count < module.statements.items.len);
        },
        else => return error.TestUnexpectedResult,
    }
}
