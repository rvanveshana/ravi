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

test "English print uses the shared print operation" {
    // Output is an effect; print returns none in both source profiles.
    try std.testing.expectEqual(@as(i64, 0), try helpers.run("print(3)\n", .en));
    var english = try helpers.compileSource("print(3)\n", .en);
    defer english.deinit();
    var kannada = try helpers.compileSource("mudrisu(3)\n", .kn);
    defer kannada.deinit();
    try std.testing.expectEqualDeep(english.code.items, kannada.code.items);
}

test "vidha/type reports runtime value categories" {
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("vidha(42)\n", .kn));
    try std.testing.expectEqual(@as(i64, 4), try helpers.run("vidha(\"ravi\")\n", .kn));
    try std.testing.expectEqual(@as(i64, 2), try helpers.run("vidha([1, 2])\n", .kn));
}

test "string indexing returns UTF-8 code points" {
    try std.testing.expectEqual(@as(i64, 0xC0), try helpers.run("\"AÀ\"[1]\n", .kn));
}

test "capture-free anonymous functions are executable values" {
    try std.testing.expectEqual(@as(i64, 8), try helpers.run("double = kriya(value: int) => value * 2\ndouble(4)\n", .kn));
}

test "anonymous functions capture heap-backed environments" {
    try std.testing.expectEqual(@as(i64, 9), try helpers.run("factor = 3\nscale = kriya(value: int) => value * factor\nscale(3)\n", .kn));
}

test "nested named functions capture enclosing parameters" {
    try std.testing.expectEqual(@as(i64, 9), try helpers.run("kriya outer(value: int):\n    kriya inner(extra: int):\n        kodu value + extra\n    kodu inner(4)\n\nouter(5)\n", .kn));
}

test "nested closures share captured cells" {
    try std.testing.expectEqual(@as(i64, 13), try helpers.run("kriya outer(value: int):\n    kriya first(extra: int):\n        kodu value + extra\n    kriya second(extra: int):\n        kodu value + extra\n    kodu first(1) + second(2)\n\nouter(5)\n", .kn));
}

test "captured closure assignment updates its shared cell" {
    try std.testing.expectEqual(@as(i64, 13), try helpers.run("kriya outer(value: int):\n    kriya increment(dummy: int):\n        value = value + 1\n        kodu value\n    kodu increment(0) + increment(0)\n\nouter(5)\n", .kn));
}

test "runtime division faults enter tappu handlers" {
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("result = 0\nnodu:\n    5 / 0\ntappu:\n    result = 1\nresult\n", .kn));
    try std.testing.expectEqual(@as(i64, 7), try helpers.run("kriya fail(value: int):\n    kodu value / 0\n\nresult = 0\nnodu:\n    fail(1)\ntappu:\n    result = 7\nresult\n", .kn));
}

test "runtime failures retain active Ravi frames and source locations" {
    const source = "kriya fail(value: int):\n    kodu value / 0\n\nfail(2)\n";
    var chunk = try helpers.compileSource(source, .kn);
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
    try std.testing.expectEqual(@as(i64, 5), try helpers.run("values = [2, 4, 6, 8]\nvalues[1:3][0] + 1\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("\"AÀB\"[1:3] == \"ÀB\"\n", .kn));
}

test "yese raises a runtime exception value" {
    try std.testing.expectError(error.RaisedException, helpers.run("yese 42\n", .kn));
}

test "nodu tappu and kone execute explicit raise recovery" {
    try std.testing.expectEqual(@as(i64, 9), try helpers.run("result = 0\nnodu:\n    yese 7\ntappu:\n    result = 9\nresult\n", .kn));
}

test "strings support split, join, replace, and find" {
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("text = \"a,b\"\nparts = text.ode(\",\")\nparts[1] == \"b\"\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("text = \"ravi\"\ntext.huduk(\"av\") >= 0\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("text = \"ravi\"\ntext.badla(\"ra\", \"pa\") == \"pavi\"\n", .kn));
    try std.testing.expectEqual(@as(i64, 1), try helpers.run("parts = [\"ra\", \"vi\"]\nseparator = \", \"\nseparator.jote(parts) == \"ra, vi\"\n", .kn));
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

test "unresolved imports are rejected before VM execution" {
    try std.testing.expectError(error.InvalidName, helpers.run("math inda add tago\n", .kn));
    try std.testing.expectError(error.InvalidName, helpers.run("# ravi: language=en\nmath from add import\n", .en));
}
