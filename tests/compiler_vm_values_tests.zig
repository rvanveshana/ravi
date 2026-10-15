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

test "formatted strings apply width and alignment specifications" {
    var scan = try lexer.Lexer.init(std.testing.allocator, "value = 7\nf\"[{value:>4}][{value:<4}][{value:^5}]\"\n");
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.init(std.testing.allocator, tokens);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    var chunk = try compile.lowerModule(&module);
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
    for (first..module.expressions.items.len) |id| try module.collection_items.append(std.testing.allocator, @intCast(id));
    const array_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .array = .{ .first = first, .count = 2 } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .expression = @intCast(array_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.lowerModule(&module);
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
    for (tuple_first..module.expressions.items.len) |id| try module.collection_items.append(std.testing.allocator, @intCast(id));
    const tuple_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .tuple = .{ .first = tuple_first, .count = 2 } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .expression = @intCast(tuple_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.lowerModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const tuple = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .tuple), tuple.handleKind());

    module.statements.items[0].kind = .{ .expression = @intCast(tuple_id) };
    module.expressions.items[tuple_id].kind = .{ .set = .{ .first = tuple_first, .count = 2 } };
    var set_chunk = try compile.lowerModule(&module);
    defer set_chunk.deinit();
    const set = try vm.runValue(&set_chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .set), set.handleKind());

    const map_first = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 4 } });
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 3, .last = 4, .line = 1 }, .kind = .{ .integer = 9 } });
    const map_items = module.collection_items.items.len;
    for (map_first..module.expressions.items.len) |id| try module.collection_items.append(std.testing.allocator, @intCast(id));
    const map_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .map = .{ .first = map_items, .count = 1 } } });
    module.statements.items[0].kind = .{ .expression = @intCast(map_id) };
    var map_chunk = try compile.lowerModule(&module);
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
    for (first..module.expressions.items.len) |id| try module.collection_items.append(std.testing.allocator, @intCast(id));
    const array_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 5, .line = 1 }, .kind = .{ .array = .{ .first = first, .count = 2 } } });
    const zero_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 1, .line = 1 }, .kind = .{ .integer = 0 } });
    const index_id = module.expressions.items.len;
    try module.expressions.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .index = .{ .object = @intCast(array_id), .index = @intCast(zero_id) } } });
    try module.statements.append(std.testing.allocator, .{ .span = .{ .first = 0, .last = 7, .line = 1 }, .kind = .{ .expression = @intCast(index_id) } });
    var compile = compiler.Compiler.init(std.testing.allocator);
    var chunk = try compile.lowerModule(&module);
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
    for (first..module.expressions.items.len) |id| try module.collection_items.append(std.testing.allocator, @intCast(id));
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
    var chunk = try compile.lowerModule(&module);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(?vm_mod.RuntimeValue.ObjectKind, .array), result.handleKind());
}
