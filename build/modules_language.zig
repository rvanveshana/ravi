const std = @import("std");
const core = @import("modules_core.zig");
const compiler = @import("modules_compiler.zig");

pub const LanguageModules = struct {
    syntax: *std.Build.Module,
    parser: *std.Build.Module,
    formatter: *std.Build.Module,
    resolver: *std.Build.Module,
    artifact: *std.Build.Module,
    cache: *std.Build.Module,
    loader: *std.Build.Module,
    lsp: *std.Build.Module,
    lsp_protocol: *std.Build.Module,
    jsonrpc: *std.Build.Module,
    dap: *std.Build.Module,
};

pub fn addRootImports(root: *std.Build.Module, modules: core.CoreModules, runtime_modules: @import("modules_runtime.zig").RuntimeModules, compiler_modules: compiler.CompilerModules, language_modules: LanguageModules) void {
    root.addImport("ravi_config", modules.config);
    root.addImport("ravi_ast", modules.ast);
    root.addImport("ravi_types", modules.types);
    root.addImport("ravi_bytecode", modules.bytecode);
    root.addImport("ravi_vm", runtime_modules.vm);
    root.addImport("ravi_gc", modules.gc);
    root.addImport("ravi_lexer", modules.lexer);
    root.addImport("ravi_hir_pipeline", compiler_modules.hir_pipeline);
    root.addImport("ravi_hir_compatibility", compiler_modules.hir_compatibility);
    root.addImport("ravi_backend", compiler_modules.backend);
    root.addImport("ravi_optimizer", compiler_modules.optimizer);
    root.addImport("ravi_debug", modules.debug);
    root.addImport("ravi_scheduler", modules.scheduler);
    root.addImport("ravi_async_state", modules.async_state);
    root.addImport("ravi_syntax", language_modules.syntax);
    root.addImport("ravi_source", modules.source);
    root.addImport("ravi_diagnostics", modules.diagnostics);
    root.addImport("ravi_formatter", language_modules.formatter);
    root.addImport("ravi_loader", language_modules.loader);
    root.addImport("ravi_parser", language_modules.parser);
    root.addImport("ravi_dap", language_modules.dap);
    root.addImport("ravi_lsp_jsonrpc", language_modules.jsonrpc);
    root.addImport("ravi_semantic_symbols", compiler_modules.semantic_symbols);
}

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, modules: core.CoreModules) LanguageModules {
    const syntax = b.createModule(.{ .root_source_file = b.path("src/syntax/syntax.zig"), .target = target, .optimize = optimize });
    syntax.addImport("ravi_lexer", modules.lexer);
    const parser = b.createModule(.{ .root_source_file = b.path("src/parser/parser.zig"), .target = target, .optimize = optimize });
    parser.addImport("ravi_lexer", modules.lexer);
    parser.addImport("ravi_ast", modules.ast);
    parser.addImport("ravi_config", modules.config);
    const formatter = b.createModule(.{ .root_source_file = b.path("src/formatter/formatter.zig"), .target = target, .optimize = optimize });
    const resolver = b.createModule(.{ .root_source_file = b.path("src/modules/resolver.zig"), .target = target, .optimize = optimize });
    const artifact = b.createModule(.{ .root_source_file = b.path("src/modules/artifact.zig"), .target = target, .optimize = optimize });
    const cache = b.createModule(.{ .root_source_file = b.path("src/modules/cache.zig"), .target = target, .optimize = optimize });
    const loader = b.createModule(.{ .root_source_file = b.path("src/modules/loader.zig"), .target = target, .optimize = optimize });
    loader.addImport("ravi_lexer", modules.lexer);
    loader.addImport("ravi_parser", parser);
    loader.addImport("ravi_ast", modules.ast);
    loader.addImport("ravi_config", modules.config);
    loader.addImport("ravi_artifact", artifact);
    const lsp = b.createModule(.{ .root_source_file = b.path("src/lsp/server.zig"), .target = target, .optimize = optimize });
    lsp.addImport("ravi_lexer", modules.lexer);
    lsp.addImport("ravi_parser", parser);
    lsp.addImport("ravi_config", modules.config);
    lsp.addImport("ravi_formatter", formatter);
    const lsp_protocol = b.createModule(.{ .root_source_file = b.path("src/lsp/protocol.zig"), .target = target, .optimize = optimize });
    const jsonrpc = b.createModule(.{ .root_source_file = b.path("src/lsp/jsonrpc.zig"), .target = target, .optimize = optimize });
    jsonrpc.addImport("ravi_lsp_protocol", lsp_protocol);
    jsonrpc.addImport("ravi_lsp_server", lsp);
    jsonrpc.addImport("ravi_config", modules.config);
    const dap = b.createModule(.{ .root_source_file = b.path("src/debug/dap.zig"), .target = target, .optimize = optimize });
    dap.addImport("ravi_lsp_protocol", lsp_protocol);
    dap.addImport("ravi_debug", modules.debug);
    return .{ .syntax = syntax, .parser = parser, .formatter = formatter, .resolver = resolver, .artifact = artifact, .cache = cache, .loader = loader, .lsp = lsp, .lsp_protocol = lsp_protocol, .jsonrpc = jsonrpc, .dap = dap };
}
