const std = @import("std");
const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");
const legacy_compiler = @import("ravi_compiler");

pub fn lower(allocator: std.mem.Allocator, module: *const ast.Module) !bytecode.Chunk {
    var compiler = legacy_compiler.Compiler.initWithLanguage(allocator, module.language);
    return compiler.compileAstModule(module);
}
