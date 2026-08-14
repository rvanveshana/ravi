const std = @import("std");
const bytecode = @import("ravi_bytecode");
const compiler = @import("ravi_compiler");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
const vm_mod = @import("ravi_vm");

pub fn compileSource(source: []const u8, language: anytype) !bytecode.Chunk {
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

pub fn run(source: []const u8, language: anytype) !i64 {
    return runAst(source, language);
}

pub fn runAst(source: []const u8, language: anytype) !i64 {
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
