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
    var chunk = try helpers.compileSource(source, .kn);
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
    try std.testing.expectEqual(@as(i64, 2), try helpers.runAst(source, .kn));
}

test "parsed AST typed function parameters bind as locals" {
    const source = "kriya double(value: int):\n    kodu value * 2\ndouble(3)\n";
    try std.testing.expectEqual(@as(i64, 6), try helpers.runAst(source, .kn));
}

test "parsed AST typed function with comments and builtin call" {
    const source = "# header\nkriya double(value: int):\n    kodu value * 2\n\nmudrisu(double(3))\n";
    try std.testing.expectEqual(@as(i64, 0), try helpers.runAst(source, .kn));
}

test "parsed AST lowers membership and identity expressions" {
    try std.testing.expectEqual(@as(i64, 0), try helpers.runAst("mudrisu(4 alli [1, 4, 6])\n", .kn));
    try std.testing.expectEqual(@as(i64, 0), try helpers.runAst("mudrisu(none ide none)\n", .kn));
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

test "multiple callback function bodies verify from independent stack depths" {
    const source = "kriya first():\n    yese 1\nkriya second():\n    yese 2\ncallbacks = [first, second]\ncallbacks[0]()\n";
    try std.testing.expectError(error.RaisedException, helpers.runAst(source, .kn));
}

test "parsed AST lowers profile print builtins" {
    const source = "mudrisu(2 + 3)\n";
    try std.testing.expectEqual(@as(i64, 0), try helpers.runAst(source, .kn));
}

test "parsed AST sleep blocks without changing sequential results" {
    try std.testing.expectEqual(@as(i64, 42), try helpers.runAst("malagu(1)\n42\n", .kn));
    try std.testing.expectEqual(@as(i64, 42), try helpers.runAst("sleep(1)\n42\n", .en));
    try std.testing.expectError(error.TypeGuardFailed, helpers.runAst("malagu(-1)\n42\n", .kn));
}

test "spawn and wait execute a function in isolated VM state" {
    const kannada_source = "kriya add(a, b):\n    kodu a + b\ntask = horabidu add(2, 3)\nkaayu task\n";
    try std.testing.expectEqual(@as(i64, 5), try helpers.runAst(kannada_source, .kn));
    const english_source = "function add(a, b):\n    return a + b\ntask = spawn add(2, 3)\nwait task\n";
    try std.testing.expectEqual(@as(i64, 5), try helpers.runAst(english_source, .en));
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
    try std.testing.expectEqual(@as(i64, 9), try helpers.runAst(source, .kn));
}

test "parsed AST finally runs before loop continue" {
    const source = "value = 0\nprati item alli [1, 2, 3]:\n    nodu:\n        value = value + 1\n        adre item == 2:\n            munde\n        value = value + 10\n    kone:\n        value = value + 100\nvalue\n";
    try std.testing.expectEqual(@as(i64, 323), try helpers.runAst(source, .kn));
}

test "parsed AST finally runs before loop break" {
    const source = "value = 0\nprati item alli [1, 2, 3]:\n    nodu:\n        value = value + 1\n        adre item == 2:\n            nillu\n        value = value + 10\n    kone:\n        value = value + 100\nvalue\n";
    try std.testing.expectEqual(@as(i64, 212), try helpers.runAst(source, .kn));
}

