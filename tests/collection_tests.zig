const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const vm_mod = @import("ravi_vm");
const compiler = @import("ravi_compiler");

const collection_primitives = vm_mod.collection_primitives;
const Value = vm_mod.RuntimeValue;

test "array primitives preserve ordered mutation semantics" {
    var array = collection_primitives.Array.init(std.testing.allocator);
    defer array.deinit();
    try collection_primitives.append(&array, Value.fromInt(4));
    try collection_primitives.append(&array, Value.fromInt(6));
    try collection_primitives.insert(&array, 1, Value.fromInt(5));
    try std.testing.expectEqual(@as(usize, 3), array.len);
    try std.testing.expect(collection_primitives.contains(&array, Value.fromInt(5)));
    try std.testing.expectEqual(@as(i64, 5), (try collection_primitives.pop(&array, 1)).asInt());
    try std.testing.expect(!collection_primitives.contains(&array, Value.fromInt(5)));
    collection_primitives.clear(&array);
    try std.testing.expectEqual(@as(usize, 0), array.len);
}

test "dictionary primitives update and remove keys" {
    var dictionary = collection_primitives.Dict.init(std.testing.allocator);
    defer dictionary.deinit();
    try collection_primitives.put(&dictionary, Value.fromInt(7), Value.fromInt(70));
    try collection_primitives.put(&dictionary, Value.fromInt(7), Value.fromInt(77));
    try std.testing.expectEqual(@as(usize, 1), dictionary.len);
    try std.testing.expectEqual(@as(i64, 77), (collection_primitives.get(&dictionary, Value.fromInt(7)).?).asInt());
    try std.testing.expectEqual(@as(i64, 77), (try collection_primitives.remove(&dictionary, Value.fromInt(7))).asInt());
    try std.testing.expectEqual(@as(usize, 0), dictionary.len);
}

test "dictionary numeric keys share mixed integer and float equality" {
    var dictionary = collection_primitives.Dict.init(std.testing.allocator);
    defer dictionary.deinit();
    try collection_primitives.put(&dictionary, Value.fromInt(3), Value.fromInt(30));
    try std.testing.expectEqual(@as(usize, 1), dictionary.len);
    try std.testing.expectEqual(@as(i64, 30), (collection_primitives.get(&dictionary, Value.fromFloat(3.0)).?).asInt());
    try collection_primitives.put(&dictionary, Value.fromFloat(3.0), Value.fromInt(33));
    try std.testing.expectEqual(@as(usize, 1), dictionary.len);
    try std.testing.expectEqual(@as(i64, 33), (collection_primitives.get(&dictionary, Value.fromInt(3)).?).asInt());
}

test "dictionary hash storage keeps colliding keys reachable" {
    var dictionary = collection_primitives.Dict.init(std.testing.allocator);
    defer dictionary.deinit();
    try collection_primitives.put(&dictionary, Value.fromInt(1), Value.fromInt(10));
    try collection_primitives.put(&dictionary, Value.fromInt(65), Value.fromInt(650));
    try std.testing.expectEqual(@as(i64, 10), collection_primitives.get(&dictionary, Value.fromInt(1)).?.asInt());
    try std.testing.expectEqual(@as(i64, 650), collection_primitives.get(&dictionary, Value.fromInt(65)).?.asInt());
    _ = try collection_primitives.remove(&dictionary, Value.fromInt(1));
    try std.testing.expectEqual(@as(i64, 650), collection_primitives.get(&dictionary, Value.fromInt(65)).?.asInt());
}

test "source list methods support sort reverse count and pop" {
    const source = "values = [3, 1, 2]\nvalues.jodisu()\nmudrisu(values[0])\nvalues.ultha()\nmudrisu(values[0])\nmudrisu(values.enisu())\nmudrisu(values.kithu())\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "source dictionary methods use hashed storage" {
    const source = "scores = {1: 90, 2: 80}\nmudrisu(scores.tago(1))\nscores.badala(3, 70)\nmudrisu(scores.olagide(3))\nscores.tegi(1)\nmudrisu(scores.olagide(1))\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "source indexing supports list and dictionary updates" {
    const source = "values = [1, 2]\nvalues[1] = 9\nscores = {1: 10}\nscores[1] = 20\nmudrisu(values[1])\nmudrisu(scores[1])\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "source dictionaries expose views and keyed pop" {
    const source = "scores = {1: 10, 2: 20}\nkeys = scores.kili()\nvalues = scores.bele()\nitems = scores.jodi()\nmudrisu(keys[0])\nmudrisu(values[0])\nmudrisu(items[0])\nscores.tegi(1)\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "sets remove duplicates and provide set algebra" {
    const source = "left = {1, 2, 2}\nright = {2, 3}\ncombined = left.koodu(right)\ncommon = left.ondu(right)\nonly_left = left.bere(right)\nmudrisu(combined[2])\nmudrisu(common[0])\nmudrisu(only_left[0])\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "source strings are managed by the VM" {
    const source = "name = \"Ravi\"\ngreeting = \"Hi \" + name\nmudrisu(greeting)\nmudrisu(name[1])\nmudrisu(name == \"Ravi\")\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "managed strings grow beyond the former 255 byte limit" {
    var literal: [302]u8 = undefined;
    literal[0] = '"';
    @memset(literal[1..301], 'a');
    literal[301] = '"';

    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    const string_index = try chunk.addString(&literal);
    try chunk.emit(.{ .op = .make_string, .operand = @intCast(string_index) });
    try chunk.emit(.{ .op = .length });
    try chunk.emit(.{ .op = .return_value });

    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 300), try vm.run(&chunk));
}

test "VM collections grow beyond former literal capacities" {
    var array_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer array_chunk.deinit();
    for (0..300) |index| try array_chunk.emit(.{ .op = .constant, .operand = @intCast(index) });
    try array_chunk.emit(.{ .op = .make_array, .operand = 300 });
    try array_chunk.emit(.{ .op = .length });
    try array_chunk.emit(.{ .op = .return_value });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 300), try vm.run(&array_chunk));

    var dict_chunk = bytecode.Chunk.init(std.testing.allocator);
    defer dict_chunk.deinit();
    for (0..200) |index| {
        try dict_chunk.emit(.{ .op = .constant, .operand = @intCast(index) });
        try dict_chunk.emit(.{ .op = .constant, .operand = @intCast(index * 2) });
    }
    try dict_chunk.emit(.{ .op = .make_dict, .operand = 200 });
    try dict_chunk.emit(.{ .op = .length });
    try dict_chunk.emit(.{ .op = .return_value });
    try std.testing.expectEqual(@as(i64, 200), try vm.run(&dict_chunk));
}

test "VM object tables grow beyond former fixed capacities" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    _ = try chunk.addClass(.{ .name = "Object" });
    for (0..200) |_| {
        try chunk.emit(.{ .op = .make_array, .operand = 0 });
        try chunk.emit(.{ .op = .pop });
    }
    for (0..100) |_| {
        try chunk.emit(.{ .op = .make_instance, .operand = 0 });
        try chunk.emit(.{ .op = .pop });
    }
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .return_value });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 42), try vm.run(&chunk));
}

test "English dictionary pop accepts a key" {
    const source = "# ravi: language=en\nscores = {1: 10}\nprint(scores.pop(1))\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .en);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .en);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "string methods lower upper and strip" {
    const source = "spaced = \"  Ravi  \"\nmudrisu(spaced.kadi())\nname = \"Ravi\"\nmudrisu(name.doddu())\nupper = \"RAVI\"\nmudrisu(upper.chikku())\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}
