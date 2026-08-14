const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const vm_mod = @import("ravi_vm");
const dispatch = @import("ravi_dispatch");
const compiler = @import("ravi_compiler");
const ast = @import("ravi_ast");
const parser = @import("ravi_parser");

fn compileSource(source: []const u8, language: anytype) !bytecode.Chunk {
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, language);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, language);
    var module = try parse.parseRecovering();
    defer module.deinit();
    if (module.diagnostics.items.len != 0) return error.InvalidExpression;
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, language);
    return compile.compileAstModule(&module);
}

fn run(source: []const u8, language: anytype) !i64 {
    return runAst(source, language);
}

fn runAst(source: []const u8, language: anytype) !i64 {
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, language);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, language);
    var module = try parse.parseRecovering();
    defer module.deinit();
    if (module.diagnostics.items.len != 0) return error.InvalidExpression;
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, language);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    return vm.run(&chunk);
}

test "guards and arithmetic execute in the VM" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .guard_integer });
    try chunk.emit(.{ .op = .return_value });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 42), try vm.run(&chunk));
    var float_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer float_chunk.deinit();
    try float_chunk.emit(.{ .op = .constant, .operand = 1 });
    try float_chunk.emit(.{ .op = .guard_float });
    try float_chunk.emit(.{ .op = .return_value });
    try std.testing.expectError(error.TypeGuardFailed, vm.run(&float_chunk));
}

test "nested generator suspension metadata stays with the nested function" {
    const source = "kriya outer():\n    kriya inner():\n        taru 1\n    kodu 2\n";
    var chunk = try compileSource(source, .kn);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.functions.items.len);
    try std.testing.expect(!chunk.functions.items[0].resumable);
    try std.testing.expectEqual(@as(usize, 0), chunk.functions.items[0].suspension_count);
    try std.testing.expect(chunk.functions.items[1].resumable);
    try std.testing.expectEqual(@as(usize, 1), chunk.functions.items[1].suspension_count);
}

test "AST scalar lowering executes through the VM" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const left = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 2 } });
    const right = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 2, .last = 3, .line = 1 }, .kind = .{ .integer = 3 } });
    const result = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 3, .line = 1 }, .kind = .{ .binary = .{ .op = .add, .left = @intCast(left), .right = @intCast(right) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 3, .line = 1 }, .kind = .{ .expression = @intCast(result) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 5), try vm.run(&chunk));
}

test "AST scalar lowering rejects invalid expression ids" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .expression = 7 } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    try std.testing.expectError(error.InvalidExpression, compile.compileAstModule(&module));
}

test "parsed AST functions bind parameters and return values" {
    const source = "kriya add(a, b):\n    kodu a + b\nadd(2, 3)\n";
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
    try std.testing.expectEqual(@as(i64, 5), try vm.run(&chunk));
}

test "parsed AST named functions capture and mutate outer locals" {
    const source = "value = 0\nkriya inc():\n    value = value + 1\n    kodu value\ninc()\ninc()\n";
    try std.testing.expectEqual(@as(i64, 2), try runAst(source, .kn));
}

test "parsed AST typed function parameters bind as locals" {
    const source = "kriya double(value: int):\n    kodu value * 2\ndouble(3)\n";
    try std.testing.expectEqual(@as(i64, 6), try runAst(source, .kn));
}

test "parsed AST typed function with comments and builtin call" {
    const source = "# header\nkriya double(value: int):\n    kodu value * 2\n\nmudrisu(double(3))\n";
    try std.testing.expectEqual(@as(i64, 0), try runAst(source, .kn));
}

test "parsed AST lowers membership and identity expressions" {
    try std.testing.expectEqual(@as(i64, 0), try runAst("mudrisu(4 alli [1, 4, 6])\n", .kn));
    try std.testing.expectEqual(@as(i64, 0), try runAst("mudrisu(none ide none)\n", .kn));
}

test "parsed AST lambdas produce callable function values" {
    const source = "add = function(a, b) => a + b\nadd(4, 6)\n";
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

test "parsed AST lowers profile print builtins" {
    const source = "mudrisu(2 + 3)\n";
    try std.testing.expectEqual(@as(i64, 0), try runAst(source, .kn));
}

test "parsed AST sleep blocks without changing sequential results" {
    try std.testing.expectEqual(@as(i64, 42), try runAst("malagu(1)\n42\n", .kn));
    try std.testing.expectEqual(@as(i64, 42), try runAst("sleep(1)\n42\n", .en));
    try std.testing.expectError(error.TypeGuardFailed, runAst("malagu(-1)\n42\n", .kn));
}

test "spawn and wait execute a function in isolated VM state" {
    const kannada_source = "kriya add(a, b):\n    kodu a + b\ntask = horabidu add(2, 3)\nkaayu task\n";
    try std.testing.expectEqual(@as(i64, 5), try runAst(kannada_source, .kn));
    const english_source = "function add(a, b):\n    return a + b\ntask = spawn add(2, 3)\nwait task\n";
    try std.testing.expectEqual(@as(i64, 5), try runAst(english_source, .en));
}

test "parsed AST lambdas capture outer locals" {
    const source = "value = 7\nread = function() => value\nread()\n";
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

test "parsed AST closures preserve multiple capture slots" {
    const source = "left = 4\nright = 9\ncombine = function() => left + right\ncombine()\n";
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
    try std.testing.expectEqual(@as(i64, 13), try vm.run(&chunk));
}

test "parsed AST nested functions execute only through their own entry" {
    const source = "kriya outer():\n    kriya inner(value):\n        kodu value + 1\n    kodu inner(4)\nouter()\n";
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
    try std.testing.expectEqual(@as(i64, 5), try vm.run(&chunk));
}

test "parsed AST closures mutate shared captured cells" {
    const source = "value = 0\ninc = function() => value = value + 1\ninc()\ninc()\n";
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
    try std.testing.expectEqual(@as(i64, 2), try vm.run(&chunk));
}

test "parsed AST functions apply numeric default parameters" {
    const source = "kriya add(a, b = 3):\n    kodu a + b\nadd(2)\n";
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
    try std.testing.expectEqual(@as(i64, 5), try vm.run(&chunk));
}

test "parsed AST try and except recover VM faults" {
    const source = "value = 0\nnodu:\n    value = 1 / 0\ntappu:\n    value = 9\nvalue\n";
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

test "parsed AST finally runs on the normal path" {
    const source = "value = 0\nnodu:\n    value = 1\nkone:\n    value = 2\nvalue\n";
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
    try std.testing.expectEqual(@as(i64, 2), try vm.run(&chunk));
}

test "parsed AST finally runs before function return" {
    const source = "value = 0\nwork = function():\n    nodu:\n        yese 7\n    kone:\n        value = 9\nwork()\nvalue\n";
    try std.testing.expectEqual(@as(i64, 9), try runAst(source, .kn));
}

test "parsed AST finally runs before loop continue" {
    const source = "value = 0\nprati item alli [1, 2, 3]:\n    nodu:\n        value = value + 1\n        adre item == 2:\n            munde\n        value = value + 10\n    kone:\n        value = value + 100\nvalue\n";
    try std.testing.expectEqual(@as(i64, 323), try runAst(source, .kn));
}

test "parsed AST finally runs before loop break" {
    const source = "value = 0\nprati item alli [1, 2, 3]:\n    nodu:\n        value = value + 1\n        adre item == 2:\n            nillu\n        value = value + 10\n    kone:\n        value = value + 100\nvalue\n";
    try std.testing.expectEqual(@as(i64, 212), try runAst(source, .kn));
}

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
    try std.testing.expectEqual(@as(i64, 6), try runAst(one_argument, .kn));
    const two_arguments = "total = 0\nprati value alli shreni(2, 5):\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 9), try runAst(two_arguments, .kn));
    const three_arguments = "total = 0\nprati value alli shreni(1, 6, 2):\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 9), try runAst(three_arguments, .kn));
}

test "parsed AST nested for loops keep independent iterators" {
    const source = "total = 0\nprati outer alli shreni(2):\n    prati inner alli [1, 2]:\n        total = total + outer + inner\ntotal\n";
    try std.testing.expectEqual(@as(i64, 8), try runAst(source, .kn));
}

test "parsed AST continue advances range loops" {
    const source = "total = 0\nprati value alli shreni(5):\n    adre value == 2:\n        munde\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 8), try runAst(source, .kn));
}

test "parsed AST continue advances collection loops" {
    const source = "total = 0\nprati value alli [1, 2, 3]:\n    adre value == 2:\n        munde\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 4), try runAst(source, .kn));
}

test "parsed AST for loops iterate dictionary keys" {
    const source = "scores = {1: 2, 2: 3}\ntotal = 0\nprati key alli scores:\n    total = total + scores[key]\ntotal\n";
    try std.testing.expectEqual(@as(i64, 5), try runAst(source, .kn));
}

test "parsed AST dictionary views iterate values and items" {
    const values_source = "scores = {1: 2, 2: 3}\ntotal = 0\nprati value alli scores.bele():\n    total = total + value\ntotal\n";
    try std.testing.expectEqual(@as(i64, 5), try runAst(values_source, .kn));
    const items_source = "scores = {1: 2, 2: 3}\ntotal = 0\nprati item alli scores.jodi():\n    total = total + item[0] + item[1]\ntotal\n";
    try std.testing.expectEqual(@as(i64, 8), try runAst(items_source, .kn));
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
    try std.testing.expectEqual(@as(i64, 11), try runAst(source, .kn));
}

test "parsed AST exception matching rethrows unmatched payload" {
    const source = "nodu:\n    yese 7\ntappu 8:\n    11\n";
    try std.testing.expectError(error.RaisedException, runAst(source, .kn));
}

test "AST and token compilers agree on representative Phase 2 programs" {
    const sources = [_][]const u8{
        "value = 2 + 3\nvalue\n",
        "total = 0\nprati item alli [1, 2, 3]:\n    total = total + item\ntotal\n",
        "value = 0\nnodu:\n    yese 7\ntappu error:\n    value = error\nvalue\n",
    };
    for (sources) |source| try std.testing.expectEqual(try run(source, .kn), try runAst(source, .kn));
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

test "formatted strings apply width and alignment specifications" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = 7\nf\"[{value:>4}][{value:<4}][{value:^5}]\"\n");
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
    try std.testing.expectEqualStrings("[   7][7   ][  7  ]", vm.strings.items[result.handleIndex().?].bytes);
}

test "formatted strings enforce numeric type specifications" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = \"seven\"\nf\"{value:d}\"\n");
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
    try std.testing.expectError(error.TypeGuardFailed, vm.runValue(&chunk));
}

test "AST formatted strings render typed values and escaped braces" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const integer_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 7 } });
    const float_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .float = 2.5 } });
    const boolean_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .boolean = true } });
    const format_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 35, .line = 1 }, .kind = .{ .formatted_string = .{ .template = "f\"n={x}, pi={y}, ok={z}, {{done}}\"", .first_arg = 0, .arg_count = 3 } } });
    try module.format_args.append(std.testing.allocator, @intCast(integer_id));
    try module.format_args.append(std.testing.allocator, @intCast(float_id));
    try module.format_args.append(std.testing.allocator, @intCast(boolean_id));
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 35, .line = 1 }, .kind = .{ .expression = @intCast(format_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("n=7, pi=2.5, ok=true, {done}", vm.strings.items[result.handleIndex().?].bytes);
}

test "AST string lowering creates a managed string value" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const string_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .string = "\"ravi\"" } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .expression = @intCast(string_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .string), result.handleKind());
}

test "VM preserves backslashes in raw string literals" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const string_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 16, .line = 1 }, .kind = .{ .string = "r'C:\\data\\input.rk'" } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 16, .line = 1 }, .kind = .{ .expression = @intCast(string_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("C:\\data\\input.rk", vm.strings.items[result.handleIndex().?].bytes);
}

test "AST boolean lowering preserves boolean values" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const true_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 3, .line = 1 }, .kind = .{ .boolean = true } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 3, .line = 1 }, .kind = .{ .expression = @intCast(true_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expect(result.isBool());
    try std.testing.expect(result.asBool());
}

test "AST logical binary lowering returns boolean truthiness" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const left = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 4, .line = 1 }, .kind = .{ .boolean = true } });
    const right = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 5, .last = 10, .line = 1 }, .kind = .{ .boolean = false } });
    const result = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 10, .line = 1 }, .kind = .{ .binary = .{ .op = .logic_or, .left = @intCast(left), .right = @intCast(right) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 10, .line = 1 }, .kind = .{ .expression = @intCast(result) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const value = try vm.runValue(&chunk);
    try std.testing.expect(value.isBool());
    try std.testing.expect(value.asBool());
}

test "AST float lowering preserves IEEE arithmetic and comparisons" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const left = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 3, .line = 1 }, .kind = .{ .float = 1.5 } });
    const right = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 6, .last = 8, .line = 1 }, .kind = .{ .float = 2.0 } });
    const result = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 8, .line = 1 }, .kind = .{ .binary = .{ .op = .multiply, .left = @intCast(left), .right = @intCast(right) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 8, .line = 1 }, .kind = .{ .expression = @intCast(result) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const value = try vm.runValue(&chunk);
    try std.testing.expect(value.isFloat());
    try std.testing.expectEqual(@as(f64, 3.0), value.asFloat());
}

test "mixed numeric operations widen integers to floats" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const integer_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 3 } });
    const float_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 4, .last = 6, .line = 1 }, .kind = .{ .float = 0.5 } });
    const result_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 6, .line = 1 }, .kind = .{ .binary = .{ .op = .add, .left = @intCast(integer_id), .right = @intCast(float_id) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 6, .line = 1 }, .kind = .{ .expression = @intCast(result_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const value = try vm.runValue(&chunk);
    try std.testing.expect(value.isFloat());
    try std.testing.expectEqual(@as(f64, 3.5), value.asFloat());
}

test "float division by zero raises the numeric runtime error" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const numerator = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 2, .line = 1 }, .kind = .{ .float = 1.0 } });
    const denominator = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 5, .last = 7, .line = 1 }, .kind = .{ .float = 0.0 } });
    const result = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .binary = .{ .op = .divide, .left = @intCast(numerator), .right = @intCast(denominator) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .expression = @intCast(result) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.DivisionByZero, vm.runValue(&chunk));
}

test "AST array lowering creates an ordered array value" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const first = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 7 } });
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 3, .last = 4, .line = 1 }, .kind = .{ .integer = 11 } });
    const array_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .array = .{ .first = first, .count = 2 } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .expression = @intCast(array_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .array), result.handleKind());
}

test "AST tuple set and map lowering creates collection values" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const tuple_first = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 1 } });
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 3, .last = 4, .line = 1 }, .kind = .{ .integer = 2 } });
    const tuple_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .tuple = .{ .first = tuple_first, .count = 2 } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .expression = @intCast(tuple_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const tuple = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .tuple), tuple.handleKind());

    module.statements.items[0].kind = .{ .expression = @intCast(tuple_id) };
    module.expressions.items[tuple_id].kind = .{ .set = .{ .first = tuple_first, .count = 2 } };
    var set_chunk = try compile.compileAstModule(&module);
    defer set_chunk.deinit();
    const set = try vm.runValue(&set_chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .set), set.handleKind());

    const map_first = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 4 } });
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 3, .last = 4, .line = 1 }, .kind = .{ .integer = 9 } });
    const map_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .map = .{ .first = map_first, .count = 2 } } });
    module.statements.items[0].kind = .{ .expression = @intCast(map_id) };
    var map_chunk = try compile.compileAstModule(&module);
    defer map_chunk.deinit();
    const map = try vm.runValue(&map_chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .dictionary), map.handleKind());
}

test "AST index lowering reads an array element" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const first = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 7 } });
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 3, .last = 4, .line = 1 }, .kind = .{ .integer = 11 } });
    const array_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .array = .{ .first = first, .count = 2 } } });
    const index_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .index = .{ .object = @intCast(array_id), .index = 0 } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .expression = @intCast(index_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
}

test "AST slice lowering creates an array range" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const first = module.expressions.items.len;
    for ([_]i64{ 3, 5, 7, 9 }) |value| {
        try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = value } });
    }
    const array_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 11, .line = 1 }, .kind = .{ .array = .{ .first = first, .count = 4 } } });
    const start_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 1 } });
    const end_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 3 } });
    const slice_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 15, .line = 1 }, .kind = .{ .slice = .{ .object = @intCast(array_id), .start = @intCast(start_id), .end = @intCast(end_id) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 15, .line = 1 }, .kind = .{ .expression = @intCast(slice_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .array), result.handleKind());
}

test "AST call lowering emits an indirect call" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const callee = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 3, .line = 1 }, .kind = .{ .name = "callback" } });
    const argument = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 4, .last = 4, .line = 1 }, .kind = .{ .integer = 8 } });
    try module.call_args.append(std.testing.allocator, @intCast(argument));
    const call_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .call = .{ .callee = @intCast(callee), .first_arg = 0, .arg_count = 1 } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .expression = @intCast(call_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileAstModule(&module);
    defer chunk.deinit();
    try std.testing.expectEqual(bytecode.OpCode.call_value, chunk.code.items[2].op);
    try std.testing.expectEqual(@as(i64, 1), chunk.code.items[2].operand);
}

test "packed release execution matches source chunk" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 19 });
    try chunk.emit(.{ .op = .constant, .operand = 23 });
    try chunk.emit(.{ .op = .add });
    try chunk.emit(.{ .op = .return_value });
    const bytes = try chunk.encodePacked(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const source_result = try vm.runValue(&chunk);
    const packed_result = try vm.runPackedValue(&chunk, bytes);
    try std.testing.expectEqual(source_result, packed_result);
}

test "VM fast dispatcher agrees with reference arithmetic execution" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 20 });
    try chunk.emit(.{ .op = .constant, .operand = 22 });
    try chunk.emit(.{ .op = .add });
    try chunk.emit(.{ .op = .return_value });
    try std.testing.expect(dispatch.FastDispatcher.supports(chunk.code.items));
    var fast_stack: [8]vm_mod.RuntimeValue = undefined;
    const direct = dispatch.FastDispatcher.dispatchLoop(chunk.code.items, &fast_stack);
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const reference = try vm.runValue(&chunk);
    switch (direct) {
        .ok => |value| try std.testing.expect(vm_mod.RuntimeValue.eql(value, reference)),
        .runtime_error => return error.UnexpectedRuntimeError,
    }
}

test "VM strings are traced and reclaimed between executions" {
    var string_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer string_chunk.deinit();
    const string_index = try string_chunk.addString("\"collector-owned\"");
    try string_chunk.emit(.{ .op = .make_string, .operand = @intCast(string_index) });
    try string_chunk.emit(.{ .op = .halt });
    var empty_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer empty_chunk.deinit();
    try empty_chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.runValue(&string_chunk);
    try std.testing.expectEqual(@as(usize, 1), vm.collector.statistics().live);
    _ = try vm.runValue(&empty_chunk);
    try std.testing.expectEqual(@as(usize, 0), vm.collector.statistics().live);
}

test "VM arrays are traced and reclaimed between executions" {
    var array_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer array_chunk.deinit();
    try array_chunk.emit(.{ .op = .constant, .operand = 7 });
    try array_chunk.emit(.{ .op = .make_array, .operand = 1 });
    try array_chunk.emit(.{ .op = .halt });
    var empty_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer empty_chunk.deinit();
    try empty_chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.runValue(&array_chunk);
    try std.testing.expectEqual(@as(usize, 1), vm.collector.statistics().live);
    _ = try vm.runValue(&empty_chunk);
    try std.testing.expectEqual(@as(usize, 0), vm.collector.statistics().live);
}

test "VM dictionaries are traced and reclaimed between executions" {
    var dictionary_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer dictionary_chunk.deinit();
    try dictionary_chunk.emit(.{ .op = .constant, .operand = 1 });
    try dictionary_chunk.emit(.{ .op = .constant, .operand = 2 });
    try dictionary_chunk.emit(.{ .op = .make_dict, .operand = 1 });
    try dictionary_chunk.emit(.{ .op = .halt });
    var empty_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer empty_chunk.deinit();
    try empty_chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.runValue(&dictionary_chunk);
    try std.testing.expectEqual(@as(usize, 1), vm.collector.statistics().live);
    _ = try vm.runValue(&empty_chunk);
    try std.testing.expectEqual(@as(usize, 0), vm.collector.statistics().live);
}

test "VM closures and cells are traced and reclaimed between executions" {
    var closure_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer closure_chunk.deinit();
    _ = try closure_chunk.addFunction(.{ .entry = 0, .arity = 0, .name = "closure", .capture_count = 0 });
    try closure_chunk.emit(.{ .op = .make_closure, .operand = 0 });
    try closure_chunk.emit(.{ .op = .halt });
    var empty_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer empty_chunk.deinit();
    try empty_chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.runValue(&closure_chunk);
    try std.testing.expectEqual(@as(usize, 1), vm.collector.statistics().live);
    _ = try vm.runValue(&empty_chunk);
    try std.testing.expectEqual(@as(usize, 0), vm.collector.statistics().live);
}

test "VM precise roots reclaim an unreachable object during execution" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 7 });
    try chunk.emit(.{ .op = .make_array, .operand = 1 });
    try chunk.emit(.{ .op = .pop });
    try chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    vm.collector.collection_threshold = 1;
    _ = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(usize, 0), vm.collector.statistics().live);
}

test "compiler emits real source locations" {
    var chunk = try compileSource("value = 40 + 2\nvalue\n", .kn);
    defer chunk.deinit();
    try std.testing.expectEqual(chunk.code.items.len, chunk.source_map.items.len);
    var located = false;
    for (chunk.source_map.items) |location| {
        if (location.line > 0 and location.end_offset > location.start_offset) located = true;
    }
    try std.testing.expect(located);
}

test "VM stack grows beyond the initial capacity" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    for (0..600) |value| try chunk.emit(.{ .op = .constant, .operand = @intCast(value) });
    try chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 599), try vm.run(&chunk));
    try std.testing.expect(vm.stack.len >= 600);
}

test "VM call frames grow for deep recursion" {
    const source = "kriya descend(value: int):\n    adre value > 0:\n        kodu descend(value - 1)\n    kodu 0\n\ndescend(100)\n";
    try std.testing.expectEqual(@as(i64, 0), try run(source, .kn));
}

test "functions support defaults, keywords, variadics, and values" {
    try std.testing.expectEqual(@as(i64, 6), try run("kriya scale(value: int, factor: int = 2):\n    kodu value * factor\n\nscale(value = 3)\n", .kn));
    try std.testing.expectEqual(@as(i64, 6), try run("kriya double(value: int):\n    kodu value * 2\n\noperation = double\noperation(3)\n", .kn));
}

test "control flow and collections execute" {
    try std.testing.expectEqual(@as(i64, 1), try run("x = 4\ny = x * 2 + 1\ny > 5\n", .kn));
    _ = try run("prati i alli shreni(1, 4, 2):\n    mudrisu(i)\n", .kn);
    _ = try run("prati i alli 4:\n    adre i == 1:\n        munde\n    adre i == 3:\n        nillu\n    mudrisu(i)\n", .kn);
    _ = try run("values = [4, 5, 6]\nmudrisu(values[1])\nprati value alli [1, 2, 3]:\n    mudrisu(value)\n", .kn);
}

test "boolean operators short circuit and unary operators follow operands" {
    try std.testing.expectEqual(@as(i64, 0), try run("0 mattu (1 / 0)\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("1 athva (1 / 0)\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("alla (1 == 2)\n", .kn));
    try std.testing.expectEqual(@as(i64, -3), try run("-3\n", .kn));
}

test "chained comparisons compare adjacent operands" {
    try std.testing.expectEqual(@as(i64, 1), try run("1 < 2 < 3\n", .kn));
    try std.testing.expectEqual(@as(i64, 0), try run("1 < 3 < 2\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("3 > 2 == 2\n", .kn));
}

test "classes create instances and dispatch methods" {
    const source = "roopa Person:\n    kriya speak():\n        kodu 42\n\np = Person()\np.speak()\n";
    try std.testing.expectEqual(@as(i64, 42), try run(source, .kn));
}

test "single inheritance is recorded in class bytecode metadata" {
    const source = "roopa Parent:\n    kodu none\nroopa Child guru Parent:\n    kodu none\n";
    var chunk = try compileSource(source, .kn);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.classes.items.len);
    try std.testing.expect(chunk.classes.items[0].base == null);
    try std.testing.expectEqual(@as(usize, 0), chunk.classes.items[1].base.?);
}

test "class method tables retain owning class and function identity" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 1\nroopa Child guru Parent:\n    kriya speak():\n        kodu 2\n";
    var chunk = try compileSource(source, .kn);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.methods.items.len);
    try std.testing.expectEqual(@as(usize, 0), chunk.methods.items[0].class_index);
    try std.testing.expectEqual(@as(usize, 1), chunk.methods.items[1].class_index);
    try std.testing.expectEqualStrings("speak", chunk.methods.items[0].name);
}

test "runtime method dispatch selects a single-inheritance override" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 1\nroopa Child guru Parent:\n    kriya speak():\n        kodu 2\nchild = Child()\nchild.speak()\n";
    try std.testing.expectEqual(@as(i64, 2), try run(source, .kn));
}

test "runtime method dispatch falls back to inherited method" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 7\nroopa Child guru Parent:\n    kriya other():\n        kodu 2\nchild = Child()\nchild.speak()\n";
    try std.testing.expectEqual(@as(i64, 7), try run(source, .kn));
}

test "runtime method dispatch can explicitly call a parent with guru" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 7\nroopa Child guru Parent:\n    kriya speak():\n        kodu guru.speak() + 1\nchild = Child()\nchild.speak()\n";
    try std.testing.expectEqual(@as(i64, 8), try run(source, .kn));
}

test "multi-level inheritance and nested object composition execute" {
    const source =
        "roopa Entity:\n" ++
        "    kriya category():\n" ++
        "        kodu 1\n" ++
        "roopa Account guru Entity:\n" ++
        "    kriya category():\n" ++
        "        kodu 2\n" ++
        "roopa Premium guru Account:\n" ++
        "    kriya category():\n" ++
        "        kodu 3\n" ++
        "roopa Enterprise guru Premium:\n" ++
        "    kriya huttu(value: int):\n" ++
        "        tanna.value = value\n" ++
        "    kriya category():\n" ++
        "        kodu 4\n" ++
        "roopa Invoice:\n" ++
        "    kriya huttu(account):\n" ++
        "        tanna.account = account\n" ++
        "    kriya category():\n" ++
        "        kodu tanna.account.category()\n" ++
        "account = Enterprise(975)\n" ++
        "invoice = Invoice(account)\n" ++
        "invoice.category()\n";
    try std.testing.expectEqual(@as(i64, 4), try run(source, .kn));
}

test "private methods cannot be called from external code" {
    const source = "roopa Secret:\n    swanta kriya hidden():\n        kodu 1\nsecret = Secret()\nsecret.hidden()\n";
    try std.testing.expectError(error.PrivateAccess, compileSource(source, .kn));
}

test "protected methods reject unrelated external callers at runtime" {
    const source = "roopa Secret:\n    vansha kriya guarded():\n        kodu 3\nsecret = Secret()\nsecret.guarded()\n";
    try std.testing.expectError(error.InvalidFunction, run(source, .kn));
}

test "protected methods are callable from descendant methods" {
    const source = "roopa Parent:\n    vansha kriya guarded():\n        kodu 8\nroopa Child guru Parent:\n    kriya expose():\n        kodu tanna.guarded()\nchild = Child()\nchild.expose()\n";
    try std.testing.expectEqual(@as(i64, 8), try run(source, .kn));
}

test "constructors initialize instance properties through tanna" {
    const source = "roopa Box:\n    kriya huttu(value: int):\n        tanna.value = value\n    kriya read():\n        kodu tanna.value\n\nbox = Box(42)\nbox.read()\n";
    try std.testing.expectEqual(@as(i64, 42), try run(source, .kn));
}

test "nested ranges keep independent cursors when names repeat" {
    try std.testing.expectEqual(@as(i64, 3), try run("prati i alli shreni(1, 4):\n    prati i alli shreni(1, 4):\n        x = i\nx\n", .kn));
}

test "English print uses the shared print operation" {
    try std.testing.expectEqual(@as(i64, 3), try run("print(3)\n", .en));
}

test "vidha/type reports runtime value categories" {
    try std.testing.expectEqual(@as(i64, 1), try run("vidha(42)\n", .kn));
    try std.testing.expectEqual(@as(i64, 4), try run("vidha(\"ravi\")\n", .kn));
    try std.testing.expectEqual(@as(i64, 2), try run("vidha([1, 2])\n", .kn));
}

test "string indexing returns UTF-8 code points" {
    try std.testing.expectEqual(@as(i64, 0xC0), try run("\"AÀ\"[1]\n", .kn));
}

test "capture-free anonymous functions are executable values" {
    try std.testing.expectEqual(@as(i64, 8), try run("double = kriya(value: int) => value * 2\ndouble(4)\n", .kn));
}

test "anonymous functions capture heap-backed environments" {
    try std.testing.expectEqual(@as(i64, 9), try run("factor = 3\nscale = kriya(value: int) => value * factor\nscale(3)\n", .kn));
}

test "nested named functions capture enclosing parameters" {
    try std.testing.expectEqual(@as(i64, 9), try run("kriya outer(value: int):\n    kriya inner(extra: int):\n        kodu value + extra\n    kodu inner(4)\n\nouter(5)\n", .kn));
}

test "nested closures share captured cells" {
    try std.testing.expectEqual(@as(i64, 8), try run("kriya outer(value: int):\n    kriya first(extra: int):\n        kodu value + extra\n    kriya second(extra: int):\n        kodu value + extra\n    kodu first(1) + second(2)\n\nouter(5)\n", .kn));
}

test "captured closure assignment updates its shared cell" {
    try std.testing.expectEqual(@as(i64, 13), try run("kriya outer(value: int):\n    kriya increment(dummy: int):\n        value = value + 1\n        kodu value\n    kodu increment(0) + increment(0)\n\nouter(5)\n", .kn));
}

test "runtime division faults enter tappu handlers" {
    try std.testing.expectEqual(@as(i64, 1), try run("nodu:\n    5 / 0\ntappu:\n    1\n", .kn));
    try std.testing.expectEqual(@as(i64, 7), try run("kriya fail(value: int):\n    kodu value / 0\n\nnodu:\n    fail(1)\ntappu:\n    7\n", .kn));
}

test "runtime failures retain active Ravi frames and source locations" {
    const source = "kriya fail(value: int):\n    kodu value / 0\n\nfail(2)\n";
    var chunk = try compileSource(source, .kn);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.DivisionByZero, vm.run(&chunk));
    try std.testing.expectEqual(@as(usize, 1), vm.trace_count);
    const frame = vm.trace[0];
    try std.testing.expectEqualStrings("fail", frame.function);
    try std.testing.expect(chunk.source_map.items[frame.instruction].line > 0);
}

test "arrays and strings support bounded slices" {
    try std.testing.expectEqual(@as(i64, 5), try run("values = [2, 4, 6, 8]\nvalues[1:3][0] + 1\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("\"AÀB\"[1:3] == \"ÀB\"\n", .kn));
}

test "yese raises a runtime exception value" {
    try std.testing.expectError(error.RaisedException, run("yese 42\n", .kn));
}

test "nodu tappu and kone execute explicit raise recovery" {
    try std.testing.expectEqual(@as(i64, 9), try run("nodu:\n    yese 7\ntappu:\n    9\n", .kn));
}

test "strings support split, join, replace, and find" {
    try std.testing.expectEqual(@as(i64, 1), try run("text = \"a,b\"\nparts = text.ode(\",\")\nparts[1] == \"b\"\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("text = \"ravi\"\ntext.huduk(\"av\") >= 0\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("text = \"ravi\"\ntext.badla(\"ra\", \"pa\") == \"pavi\"\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try run("parts = [\"ra\", \"vi\"]\nseparator = \", \"\nseparator.jote(parts) == \"ra, vi\"\n", .kn));
}

test "VM frames and closures grow beyond former 64-slot layouts" {
    var locals = bytecode.Chunk.init(std.testing.allocator);
    defer locals.deinit();
    for (0..200) |index| {
        try locals.emit(.{ .op = .constant, .operand = @intCast(index) });
        try locals.emit(.{ .op = .store_local, .operand = @intCast(index) });
    }
    try locals.emit(.{ .op = .load_local, .operand = 199 });
    try locals.emit(.{ .op = .return_value });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 199), try vm.run(&locals));

    var captures = bytecode.Chunk.init(std.testing.allocator);
    defer captures.deinit();
    try captures.emit(.{ .op = .jump, .operand = 3 });
    try captures.emit(.{ .op = .load_capture, .operand = 99 });
    try captures.emit(.{ .op = .return_value });
    _ = try captures.addFunction(.{ .entry = 1, .arity = 0, .name = "wide", .capture_count = 100 });
    for (0..100) |index| try captures.emit(.{ .op = .constant, .operand = @intCast(index) });
    try captures.emit(.{ .op = .make_closure, .operand = 0 });
    try captures.emit(.{ .op = .call_value, .operand = 0 });
    try captures.emit(.{ .op = .return_value });
    try std.testing.expectEqual(@as(i64, 99), try vm.run(&captures));
}

fn exerciseVmAllocationFailures(allocator: std.mem.Allocator) !void {
    var chunk = bytecode.Chunk.init(allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .jump, .operand = 3 });
    try chunk.emit(.{ .op = .load_capture, .operand = 79 });
    try chunk.emit(.{ .op = .return_value });
    _ = try chunk.addFunction(.{ .entry = 1, .arity = 0, .name = "allocation_test", .capture_count = 80 });
    for (0..80) |index| try chunk.emit(.{ .op = .constant, .operand = @intCast(index) });
    try chunk.emit(.{ .op = .make_closure, .operand = 0 });
    try chunk.emit(.{ .op = .call_value, .operand = 0 });
    try chunk.emit(.{ .op = .return_value });
    var vm = try vm_mod.Vm.init(allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
}

test "VM wide-frame execution propagates every allocation failure without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseVmAllocationFailures, .{});
}

test "import declarations do not read uninitialized VM locals" {
    try std.testing.expectEqual(@as(i64, 0), try run("math inda add tago\n", .kn));
    try std.testing.expectEqual(@as(i64, 0), try run("# ravi: language=en\nmath from add import\n", .en));
}
