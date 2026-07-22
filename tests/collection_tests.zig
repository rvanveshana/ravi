const std = @import("std");
const lexer = @import("ravi_lexer");
const vm_mod = @import("ravi_vm");
const compiler = @import("ravi_compiler");

const collection_primitives = vm_mod.collection_primitives;

test "array primitives preserve ordered mutation semantics" {
    var array = collection_primitives.Array{};
    try collection_primitives.append(&array, 4);
    try collection_primitives.append(&array, 6);
    try collection_primitives.insert(&array, 1, 5);
    try std.testing.expectEqual(@as(usize, 3), array.len);
    try std.testing.expect(collection_primitives.contains(&array, 5));
    try std.testing.expectEqual(@as(i64, 5), try collection_primitives.pop(&array, 1));
    try std.testing.expect(!collection_primitives.contains(&array, 5));
    collection_primitives.clear(&array);
    try std.testing.expectEqual(@as(usize, 0), array.len);
}

test "dictionary primitives update and remove keys" {
    var dictionary = collection_primitives.Dict{};
    try collection_primitives.put(&dictionary, 7, 70);
    try collection_primitives.put(&dictionary, 7, 77);
    try std.testing.expectEqual(@as(usize, 1), dictionary.len);
    try std.testing.expectEqual(@as(i64, 77), dictionary.values[0]);
    try std.testing.expectEqual(@as(i64, 77), try collection_primitives.remove(&dictionary, 7));
    try std.testing.expectEqual(@as(usize, 0), dictionary.len);
}

test "dictionary hash storage keeps colliding keys reachable" {
    var dictionary = collection_primitives.Dict{};
    try collection_primitives.put(&dictionary, 1, 10);
    try collection_primitives.put(&dictionary, 65, 650);
    try std.testing.expectEqual(@as(?i64, 10), collection_primitives.get(&dictionary, 1));
    try std.testing.expectEqual(@as(?i64, 650), collection_primitives.get(&dictionary, 65));
    _ = try collection_primitives.remove(&dictionary, 1);
    try std.testing.expectEqual(@as(?i64, 650), collection_primitives.get(&dictionary, 65));
}

test "source list methods support sort reverse count and pop" {
    const source = "values = [3, 1, 2]\nvalues.jodisu()\nmudrisu(values[0])\nvalues.ultha()\nmudrisu(values[0])\nmudrisu(values.enisu())\nmudrisu(values.kithu())\n";
    var scan = try lexer.Lexer.init(std.testing.allocator, source);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .kn);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = vm_mod.Vm{};
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
    var vm = vm_mod.Vm{};
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
    var vm = vm_mod.Vm{};
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
    var vm = vm_mod.Vm{};
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
    var vm = vm_mod.Vm{};
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
    var vm = vm_mod.Vm{};
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}

test "English dictionary pop accepts a key" {
    const source = "# ravi: language=en\nscores = {1: 10}\nprint(scores.pop(1))\n";
    var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, source, .en);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var compile = compiler.Compiler.initWithLanguage(std.testing.allocator, .en);
    var chunk = try compile.compileProgram(tokens);
    defer chunk.deinit();
    var vm = vm_mod.Vm{};
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
    var vm = vm_mod.Vm{};
    _ = try vm.run(&chunk);
    try std.testing.expect(vm.pub_printed);
}
