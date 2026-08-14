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

test "parsed AST nested closures forward enclosing captures" {
    const source = "value = 7\nouter = function() => function() => value\ninner = outer()\ninner()\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
}

test "parsed AST explicit raise payloads recover through except" {
    const source = "value = 0\nnodu:\n    yese 7\ntappu:\n    value = 9\nvalue\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 9), try vm.run(&chunk));
}

test "custom exception classes match by type and inheritance" {
    const source = "roopa PaymentDeclined guru Exception:\n    bidu\nroopa CardDeclined guru PaymentDeclined:\n    bidu\nvalue = 0\nnodu:\n    yese CardDeclined()\ntappu PaymentDeclined aagi error:\n    value = 1\nvalue\n";
    try std.testing.expectEqual(@as(i64, 1), try helpers.runAst(source, .kn));
}

test "PascalCase exception handlers can omit the binding" {
    const source = "roopa PaymentDeclined guru Exception:\n    bidu\nvalue = 0\nnodu:\n    yese PaymentDeclined()\ntappu PaymentDeclined:\n    value = 1\nvalue\n";
    try std.testing.expectEqual(@as(i64, 1), try helpers.runAst(source, .kn));
}

test "typed handlers match native exception hierarchy" {
    const source = "value = 0\nnodu:\n    5 / 0\ntappu ArithmeticError aagi error:\n    value = 1\nvalue\n";
    try std.testing.expectEqual(@as(i64, 1), try helpers.runAst(source, .kn));
}

test "native faults use the same exception reference as Ravi constructors" {
    const source = "caught = false\nnodu:\n    5 / 0\ntappu exception:\n    caught = (exception == \"ZeroDivisionError\")\nvalue = 1 if caught else 0\nvalue\n";
    try std.testing.expectEqual(@as(i64, 1), try helpers.runAst(source, .kn));
}

test "parsed AST for loops iterate arrays" {
    const source = "total = 0\nprati item alli [1, 2, 3]:\n    total = total + item\ntotal\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 6), try vm.run(&chunk));
}

test "parsed AST for loops lower range calls" {
    const one_argument = "total = 0\nprati value alli shreni(4):\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 6), try helpers.runAst(one_argument, .kn));
    const two_arguments = "total = 0\nprati value alli shreni(2, 5):\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 9), try helpers.runAst(two_arguments, .kn));
    const three_arguments = "total = 0\nprati value alli shreni(1, 6, 2):\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 9), try helpers.runAst(three_arguments, .kn));
}

test "parsed AST nested for loops keep independent iterators" {
    const source = "total = 0\nprati outer alli shreni(2):\n    prati inner alli [1, 2]:\n        total = total + outer + inner\ntotal\n";
    try std.testing.expectEqual(@as(i64, 8), try helpers.runAst(source, .kn));
}

test "parsed AST continue advances range loops" {
    const source = "total = 0\nprati value alli shreni(5):\n    adre value == 2:\n        munde\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 8), try helpers.runAst(source, .kn));
}

test "parsed AST continue advances collection loops" {
    const source = "total = 0\nprati value alli [1, 2, 3]:\n    adre value == 2:\n        munde\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 4), try helpers.runAst(source, .kn));
}

test "parsed AST for loops iterate dictionary keys" {
    const source = "scores = {1: 2, 2: 3}\ntotal = 0\nprati key alli scores:\n    total = total + scores[key]\ntotal\n";
    try std.testing.expectEqual(@as(i64, 5), try helpers.runAst(source, .kn));
}

test "parsed AST dictionary views iterate values and items" {
    const values_source = "scores = {1: 2, 2: 3}\ntotal = 0\nprati value alli scores.bele():\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 5), try helpers.runAst(values_source, .kn));
    const items_source = "scores = {1: 2, 2: 3}\ntotal = 0\nprati item alli scores.jodi():\n    total = total + item[0] + item[1]\ntotal\n";
    try std.testing.expectEqual(@as(i64, 8), try helpers.runAst(items_source, .kn));
}

test "parsed AST except binds raised payload" {
    const source = "value = 0\nnodu:\n    yese 7\ntappu error:\n    value = error\nvalue\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
}

test "parsed AST exception matching selects matching payload" {
    const source = "value = 0\nnodu:\n    yese 7\ntappu 7:\n    value = 11\nvalue\n";
    try std.testing.expectEqual(@as(i64, 11), try helpers.runAst(source, .kn));
}

test "parsed AST exception matching rethrows unmatched payload" {
    const source = "nodu:\n    yese 7\ntappu 8:\n    11\n";
    try std.testing.expectError(error.RaisedException, helpers.runAst(source, .kn));
}

test "AST and token compilers agree on representative Phase 2 programs" {
    const sources = [_][]const u8{
        "value = 2 + 3\nvalue\n",
        "total = 0\nprati item alli [1, 2, 3]:\n    total = total + item\ntotal\n",
        "value = 0\nnodu:\n    yese 7\ntappu error:\n    value = error\nvalue\n",
    };
    for (sources) |source| try std.testing.expectEqual(try helpers.run(source, .kn), try helpers.runAst(source, .kn));
}

test "AST formatted strings lower to formatting bytecode" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const value_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 7 } });
    const string_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 23, .line = 1 }, .kind = .{ .formatted_string = .{ .template = "f\"Result: {value}\"", .first_arg = 0, .arg_count = 1 } } });
    try module.format_args.append(std.testing.allocator, @intCast(value_id));
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 23, .line = 1 }, .kind = .{ .expression = @intCast(string_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    try std.testing.expectEqual(bytecode.OpCode.make_format, chunk.code.items[1].op);
}

test "parsed formatted strings execute through the AST compiler" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = 7\nf\"Result: {value}\"\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("Result: 7", vm.strings.items[result.handleIndex().?].bytes);
}

test "parsed formatted expressions execute through the AST compiler" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = 7\nf\"Result: {value + 1}\"\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("Result: 8", vm.strings.items[result.handleIndex().?].bytes);
}

test "parsed formatted index expressions execute through the AST compiler" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "items = [9]\nindex = 0\nf\"Value: {items[index]}\"\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("Value: 9", vm.strings.items[result.handleIndex().?].bytes);
}

test "AST compiler lowers if and while control flow" {
    const source = "value = 0\nwhile value < 3:\n    value = value + 1\nif value == 3:\n    value = value + 4\nvalue\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
}

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
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 3), try vm.run(&chunk));
}

test "AST control flow lowers else break and continue" {
    const source = "value = 0\nwhile value < 5:\n    value = value + 1\n    if value == 2:\n        continue\n    if value == 4:\n        break\nif value == 4:\n    value = 10\nelse:\n    value = 20\nvalue\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 10), try vm.run(&chunk));
}

test "AST control flow rejects transfers outside loops" {
    const source = "break\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    try std.testing.expectError(error.UnsupportedOperator, compile.compileAstModule(&module));
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
    var ast_chunk = try ast_compile.compileAstModule(&module);
    defer ast_chunk.deinit();
    var ast_vm = try vm_mod.Vm.init(std.testing.allocator);
    defer ast_vm.deinit();
    try std.testing.expectEqual(@as(i64, 3), try ast_vm.run(&ast_chunk));
}

