const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");
const mir = @import("ravi_mir");
const mir_bytecode = @import("ravi_mir_bytecode");
const pipeline = @import("ravi_hir_pipeline");
const std = @import("std");
const vm_runtime = @import("ravi_vm");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
test "HIR pipeline lowers simple classes and properties" {
    const source = "roopa Person:\n    saarva kriya huttu(name: string):\n        tanna.name = name\n    saarva kriya speak():\n        kodu tanna.name\np = Person(\"Ravi\")\np.speak()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 1), chunk.classes.items.len);
    try std.testing.expectEqual(@as(usize, 2), chunk.methods.items.len);
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("Ravi", vm.stringSlice(result).?);
}
test "HIR pipeline preserves class inheritance and override dispatch" {
    const source = "roopa Animal:\n    saarva kriya speak():\n        kodu \"animal\"\nroopa Dog guru Animal:\n    saarva kriya speak():\n        kodu \"dog\"\np = Dog()\np.speak()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.classes.items.len);
    try std.testing.expectEqual(@as(?usize, 0), chunk.classes.items[1].base);
    try std.testing.expectEqual(@as(?usize, 1), bytecode.lookupMethod(chunk.classes.items, chunk.methods.items, 1, "speak"));
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("dog", vm.stringSlice(result).?);
}
test "HIR pipeline lowers guru calls to the base implementation" {
    const source = "roopa Animal:\n    saarva kriya speak():\n        kodu \"animal\"\nroopa Dog guru Animal:\n    saarva kriya speak():\n        kodu guru.speak()\np = Dog()\np.speak()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqualStrings("animal", vm.stringSlice(result).?);
}
test "HIR pipeline propagates a parsed raise through the VM" {
    const source = "kriya fail():\n    yese \"boom\"\nfail()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.RaisedException, vm.runValue(&chunk));
}
test "HIR pipeline lowers a parsed try except recovery" {
    const source = "kriya recover():\n    nodu:\n        yese \"boom\"\n    tappu:\n        kodu \"recovered\"\nrecover()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqualStrings("recovered", vm.stringSlice(try vm.runValue(&chunk)).?);
}
test "HIR pipeline binds a parsed exception payload" {
    const source = "kriya recover():\n    nodu:\n        yese 7\n    tappu error:\n        kodu error\nrecover()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
}
test "HIR pipeline selects a matching parsed exception" {
    const source = "kriya recover():\n    nodu:\n        yese 7\n    tappu 7:\n        kodu 8\nrecover()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 8), try vm.run(&chunk));
}
test "HIR pipeline runs a parsed finally before returning" {
    const source = "kriya recover():\n    nodu:\n        kodu 7\n    kone:\n        marker = 9\nrecover()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
}
test "HIR pipeline marks a parsed yield function resumable" {
    const source = "kriya values():\n    yese 7\nvalues()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 1), chunk.functions.items[0].suspension_count);
    try std.testing.expect(chunk.functions.items[0].resumable);
}
test "HIR pipeline counts sequential yield suspension points" {
    const source = "kriya values():\n    yese 1\n    yese 2\n    kodu 3\nvalues()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 2), chunk.functions.items[0].suspension_count);
    try std.testing.expect(chunk.functions.items[0].resumable);
}
test "HIR pipeline preserves annotated parameter types" {
    const source = "kriya identity(value: float): float\n    kodu value\nidentity(3.5)\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    try std.testing.expectEqual(@import("ravi_hir").Type.float, chunk.functions.items[0].parameter_types.items[0]);
    try std.testing.expectEqual(@import("ravi_hir").Type.float, chunk.functions.items[0].return_type);
}
test "HIR pipeline supplies omitted integer defaults" {
    const source = "kriya identity(value: int = 7): int\n    kodu value\nidentity()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), (try vm.runValue(&chunk)).asInt());
}
test "HIR pipeline binds reordered keyword arguments" {
    const source = "kriya scale(value: int, factor: int): int\n    kodu value * factor\nscale(factor = 2, value = 3)\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 6), (try vm.runValue(&chunk)).asInt());
}
test "HIR pipeline packs variadic and keyword variadic arguments" {
    const source = "kriya collect(value: int, *values, **options): int\n    kodu value\ncollect(4, 5, 6, answer = 7)\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 4), (try vm.runValue(&chunk)).asInt());
}
test "HIR pipeline binds keyword arguments inside a function" {
    const source = "kriya scale(value: int, factor: int): int\n    kodu value * factor\nkriya invoke(): int\n    kodu scale(factor = 2, value = 3)\ninvoke()\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .kn);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parse = parser.Parser.initWithLanguage(std.testing.allocator, tokens, .kn);
    var module = try parse.parseRecovering();
    defer module.deinit();
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 6), (try vm.runValue(&chunk)).asInt());
}
test "HIR pipeline preserves mutable captured cells" {
    var main_source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer main_source.deinit();
    const captured = try main_source.appendValue(.integer, .{ .constant_integer = 41 }, 1);
    const closure = try main_source.appendValue(.dynamic, .{ .make_closure = .{ .function = 0, .captures = &[_]@import("ravi_hir").ValueId{captured} } }, 1);
    const result = try main_source.appendValue(.dynamic, .{ .call_value = .{ .callee = closure, .arguments = &.{} } }, 1);
    try main_source.appendEffect(.{ .return_value = result }, 1);
    var closure_source = @import("ravi_hir").Function.init(std.testing.allocator, "mutate_capture");
    defer closure_source.deinit();
    closure_source.capture_count = 1;
    const replacement = try closure_source.appendValue(.integer, .{ .constant_integer = 9 }, 1);
    try closure_source.appendEffect(.{ .store_capture = .{ .slot = 0, .value = replacement } }, 1);
    const value = try closure_source.appendValue(.dynamic, .{ .load_capture = 0 }, 1);
    try closure_source.appendEffect(.{ .return_value = value }, 1);
    var main = try mir.Function.lower(std.testing.allocator, &main_source);
    defer main.deinit();
    var function = try mir.Function.lower(std.testing.allocator, &closure_source);
    defer function.deinit();
    var callables = [_]*const mir.Function{&function};
    var chunk = try mir_bytecode.lowerProgram(std.testing.allocator, &main, &callables);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 9), (try vm.runValue(&chunk)).asInt());
}
test "HIR pipeline lowers indexed assignment" {
    var module = ast.Module{ .allocator = std.testing.allocator };
    defer module.deinit();
    const span = ast.Span{ .first = 0, .last = 0, .line = 1 };
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .integer = 1 } });
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .array = .{ .first = 0, .count = 1 } } });
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .integer = 0 } });
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .index = .{ .object = 1, .index = 2 } } });
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .integer = 9 } });
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .assignment = .{ .name = "item", .value = 4, .target = 3 } } });
    try module.expressions.append(std.testing.allocator, .{ .span = span, .kind = .{ .index = .{ .object = 1, .index = 2 } } });
    try module.statements.append(std.testing.allocator, .{ .span = span, .kind = .{ .expression = 5 } });
    try module.statements.append(std.testing.allocator, .{ .span = span, .kind = .{ .expression = 6 } });
    try std.testing.expect(pipeline.supports(&module));
    var chunk = try pipeline.lower(std.testing.allocator, &module);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 9), (try vm.runValue(&chunk)).asInt());
}
test "MIR class property operations execute through the VM" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "class_ops");
    defer source.deinit();
    const instance = try source.appendValue(.dynamic, .{ .make_instance = 0 }, 1);
    const value = try source.appendValue(.integer, .{ .constant_integer = 7 }, 1);
    try source.appendEffect(.{ .store_property = .{ .object = instance, .value = value, .name = "answer" } }, 1);
    const result = try source.appendValue(.dynamic, .{ .get_property = .{ .object = instance, .name = "answer" } }, 1);
    try source.appendEffect(.{ .return_value = result }, 1);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try mir_bytecode.lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    _ = try chunk.addClass(.{ .name = "Answer" });
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 7), (try vm.runValue(&chunk)).asInt());
}
