const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const vm_mod = @import("ravi_vm");
const compiler = @import("ravi_compiler");

fn run(source: []const u8, language: anytype) !i64 {
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, language);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, language);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = vm_mod.Vm{};
    return vm.run(&chunk);
}

test "guards and arithmetic execute in the VM" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .guard_integer });
    try chunk.emit(.{ .op = .return_value });
    var vm = vm_mod.Vm{};
    try std.testing.expectEqual(@as(i64, 42), try vm.run(&chunk));
    var float_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer float_chunk.deinit();
    try float_chunk.emit(.{ .op = .constant, .operand = 1 });
    try float_chunk.emit(.{ .op = .guard_float });
    try float_chunk.emit(.{ .op = .return_value });
    try std.testing.expectError(error.TypeGuardFailed, vm.run(&float_chunk));
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
