const std = @import("std");
const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");
const compiler = @import("ravi_compiler");
const dispatch = @import("ravi_dispatch");
const vm_mod = @import("ravi_vm");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
const helpers = @import("compiler_vm_test_helpers");
const compileSource = helpers.compileSource;
const run = helpers.run;
const runAst = helpers.runAst;

test "AST control flow uses canonical English profile keywords" {
    const source = "value = 1\nif value == 1:\n    value = value + 2\nvalue\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .en);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .en);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .en);
    var chunk = try compile.lowerModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 3), try vm.run(&chunk));
}

test "AST control flow lowers else break and continue" {
    const source = "value = 0\nwhile value < 5:\n    value = value + 1\n    if value == 2:\n        continue\n    if value == 4:\n        break\nif value == 4:\n    value = 10\nelse:\n    value = 20\nvalue\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .en);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .en);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .en);
    var chunk = try compile.lowerModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 10), try vm.run(&chunk));
}

test "AST control flow rejects transfers outside loops" {
    const source = "break\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .en);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .en);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .en);
    try std.testing.expectError(error.UnsupportedOperator, compile.lowerModule(&module));
}

test "pass is an executable no-op in both compiler paths" {
    const source = "value = 1\nadre value == 1:\n    bidu\nvalue = value + 2\nvalue\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);

    var ast_compile = compiler.Compiler.init(std.testing.allocator);
    var ast_chunk = try ast_compile.lowerModule(&module);
    defer ast_chunk.deinit();
    var ast_vm = try vm_mod.Vm.init(std.testing.allocator);
    defer ast_vm.deinit();
    try std.testing.expectEqual(@as(i64, 3), try ast_vm.run(&ast_chunk));
}
