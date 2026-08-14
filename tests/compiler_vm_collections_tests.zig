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
    var chunk = try helpers.compileSource("value = 40 + 2\nvalue\n", .kn);
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
    try std.testing.expectEqual(@as(i64, 0), try helpers.run(source, .kn));
}

test "functions support defaults, keywords, variadics, and values" {
    try std.testing.expectEqual(@as(i64, 6), try helpers.run("kriya scale(value: int, factor: int = 2):\n    kodu value * factor\n\nscale(value = 3)\n", .kn));
    try std.testing.expectEqual(@as(i64, 6), try helpers.run("kriya double(value: int):\n    kodu value * 2\n\noperation = double\noperation(3)\n", .kn));
}

test "control flow and collections execute" {
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("x = 4\ny = x * 2 + 1\ny > 5\n", .kn));
    _ = try helpers.run("prati i alli shreni(1, 4, 2):\n    mudrisu(i)\n", .kn);
    _ = try helpers.run("prati i alli 4:\n    adre i == 1:\n        munde\n    adre i == 3:\n        nillu\n    mudrisu(i)\n", .kn);
    _ = try helpers.run("values = [4, 5, 6]\nmudrisu(values[1])\nprati value alli [1, 2, 3]:\n    mudrisu(value)\n", .kn);
}

test "boolean operators short circuit and unary operators follow operands" {
    try std.testing.expectEqual(@as(i64, 0), try helpers.run("0 mattu (1 / 0)\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("1 athva (1 / 0)\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("alla (1 == 2)\n", .kn));
    try std.testing.expectEqual(@as(i64, -3), try helpers.run("-3\n", .kn));
}

test "chained comparisons compare adjacent operands" {
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("1 < 2 < 3\n", .kn));
    try std.testing.expectEqual(@as(i64, 0), try helpers.run("1 < 3 < 2\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("3 > 2 == 2\n", .kn));
}

test "classes create instances and dispatch methods" {
    const source = "roopa Person:\n    kriya speak():\n        kodu 42\n\np = Person()\np.speak()\n";
    try std.testing.expectEqual(@as(i64, 42), try helpers.run(source, .kn));
}

test "single inheritance is recorded in class bytecode metadata" {
    const source = "roopa Parent:\n    kodu none\nroopa Child guru Parent:\n    kodu none\n";
    var chunk = try helpers.compileSource(source, .kn);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.classes.items.len);
    try std.testing.expect(chunk.classes.items[0].base == null);
    try std.testing.expectEqual(@as(usize, 0), chunk.classes.items[1].base.?);
}

test "class method tables retain owning class and function identity" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 1\nroopa Child guru Parent:\n    kriya speak():\n        kodu 2\n";
    var chunk = try helpers.compileSource(source, .kn);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.methods.items.len);
    try std.testing.expectEqual(@as(usize, 0), chunk.methods.items[0].class_index);
    try std.testing.expectEqual(@as(usize, 1), chunk.methods.items[1].class_index);
    try std.testing.expectEqualStrings("speak", chunk.methods.items[0].name);
}

test "runtime method dispatch selects a single-inheritance override" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 1\nroopa Child guru Parent:\n    kriya speak():\n        kodu 2\nchild = Child()\nchild.speak()\n";
    try std.testing.expectEqual(@as(i64, 2), try helpers.run(source, .kn));
}

test "runtime method dispatch falls back to inherited method" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 7\nroopa Child guru Parent:\n    kriya other():\n        kodu 2\nchild = Child()\nchild.speak()\n";
    try std.testing.expectEqual(@as(i64, 7), try helpers.run(source, .kn));
}

test "runtime method dispatch can explicitly call a parent with guru" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 7\nroopa Child guru Parent:\n    kriya speak():\n        kodu guru.speak() + 1\nchild = Child()\nchild.speak()\n";
    try std.testing.expectEqual(@as(i64, 8), try helpers.run(source, .kn));
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
    try std.testing.expectEqual(@as(i64, 4), try helpers.run(source, .kn));
}

test "private methods cannot be called from external code" {
    const source = "roopa Secret:\n    swanta kriya hidden():\n        kodu 1\nsecret = Secret()\nsecret.hidden()\n";
    try std.testing.expectError(error.PrivateAccess, helpers.compileSource(source, .kn));
}

test "protected methods reject unrelated external callers at runtime" {
    const source = "roopa Secret:\n    vansha kriya guarded():\n        kodu 3\nsecret = Secret()\nsecret.guarded()\n";
    try std.testing.expectError(error.InvalidFunction, helpers.run(source, .kn));
}

test "protected methods are callable from descendant methods" {
    const source = "roopa Parent:\n    vansha kriya guarded():\n        kodu 8\nroopa Child guru Parent:\n    kriya expose():\n        kodu tanna.guarded()\nchild = Child()\nchild.expose()\n";
    try std.testing.expectEqual(@as(i64, 8), try helpers.run(source, .kn));
}

test "constructors initialize instance properties through tanna" {
    const source = "roopa Box:\n    kriya huttu(value: int):\n        tanna.value = value\n    kriya read():\n        kodu tanna.value\n\nbox = Box(42)\nbox.read()\n";
    try std.testing.expectEqual(@as(i64, 42), try helpers.run(source, .kn));
}

test "nested ranges keep independent cursors when names repeat" {
    try std.testing.expectEqual(@as(i64, 3), try helpers.run("prati i alli shreni(1, 4):\n    prati i alli shreni(1, 4):\n        x = i\nx\n", .kn));
}

