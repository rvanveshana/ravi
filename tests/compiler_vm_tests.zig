const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const vm_mod = @import("ravi_vm");
const dispatch = @import("ravi_dispatch");
const compiler = @import("ravi_compiler");

fn run(source: []const u8, language: anytype) !i64 {
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, language);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, language);
    var chunk = try compile.compileProgram(tokens);
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
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = 40 + 2\nvalue\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileProgram(tokens);
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
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.classes.items.len);
    try std.testing.expect(chunk.classes.items[0].base == null);
    try std.testing.expectEqual(@as(usize, 0), chunk.classes.items[1].base.?);
}

test "class method tables retain owning class and function identity" {
    const source = "roopa Parent:\n    kriya speak():\n        kodu 1\nroopa Child guru Parent:\n    kriya speak():\n        kodu 2\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
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

test "private methods cannot be called from external code" {
    const source = "roopa Secret:\n    swanta kriya hidden():\n        kodu 1\nsecret = Secret()\nsecret.hidden()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    try std.testing.expectError(error.PrivateAccess, compile.compileProgram(tokens));
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
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.compileProgram(tokens);
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
