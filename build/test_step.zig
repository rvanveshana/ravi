const std = @import("std");

pub const TestArtifacts = struct {
    lexer: *std.Build.Step,
    parser: *std.Build.Step,
    compiler_vm: []const *std.Build.Step,
    semantic: *std.Build.Step,
    semantic_symbols: *std.Build.Step,
    value: *std.Build.Step,
    collection: *std.Build.Step,
    string_runtime: *std.Build.Step,
    backend: *std.Build.Step,
    optimizer: *std.Build.Step,
    debug: *std.Build.Step,
    dap: *std.Build.Step,
    scheduler: *std.Build.Step,
    async_state: *std.Build.Step,
    gc: *std.Build.Step,
    nan_value: *std.Build.Step,
    dispatch: *std.Build.Step,
    bytecode: *std.Build.Step,
    opcode_spec: *std.Build.Step,
    source: *std.Build.Step,
    diagnostics: *std.Build.Step,
    formatter: *std.Build.Step,
    resolver: *std.Build.Step,
    loader: *std.Build.Step,
    module_artifact: *std.Build.Step,
    module_cache: *std.Build.Step,
    hir: *std.Build.Step,
    mir: *std.Build.Step,
    mir_split: *std.Build.Step,
    mir_bytecode: *std.Build.Step,
    hir_pipeline: *std.Build.Step,
    lsp: *std.Build.Step,
    lsp_protocol: *std.Build.Step,
    jsonrpc: *std.Build.Step,
    phase0: *std.Build.Step,
    phase1: *std.Build.Step,
};

pub fn addTestStep(b: *std.Build, artifacts: TestArtifacts) void {
    const test_step = b.step("test", "Run runtime unit tests");
    test_step.dependOn(artifacts.lexer);
    test_step.dependOn(artifacts.parser);
    for (artifacts.compiler_vm) |compiler_vm_test| test_step.dependOn(compiler_vm_test);
    test_step.dependOn(artifacts.semantic);
    test_step.dependOn(artifacts.semantic_symbols);
    test_step.dependOn(artifacts.value);
    test_step.dependOn(artifacts.collection);
    test_step.dependOn(artifacts.string_runtime);
    test_step.dependOn(artifacts.backend);
    test_step.dependOn(artifacts.optimizer);
    test_step.dependOn(artifacts.debug);
    test_step.dependOn(artifacts.dap);
    test_step.dependOn(artifacts.scheduler);
    test_step.dependOn(artifacts.async_state);
    test_step.dependOn(artifacts.gc);
    test_step.dependOn(artifacts.nan_value);
    test_step.dependOn(artifacts.dispatch);
    test_step.dependOn(artifacts.bytecode);
    test_step.dependOn(artifacts.opcode_spec);
    test_step.dependOn(artifacts.source);
    test_step.dependOn(artifacts.diagnostics);
    test_step.dependOn(artifacts.formatter);
    test_step.dependOn(artifacts.resolver);
    test_step.dependOn(artifacts.loader);
    test_step.dependOn(artifacts.module_artifact);
    test_step.dependOn(artifacts.module_cache);
    test_step.dependOn(artifacts.hir);
    test_step.dependOn(artifacts.mir);
    test_step.dependOn(artifacts.mir_split);
    test_step.dependOn(artifacts.mir_bytecode);
    test_step.dependOn(artifacts.hir_pipeline);
    test_step.dependOn(artifacts.lsp);
    test_step.dependOn(artifacts.lsp_protocol);
    test_step.dependOn(artifacts.jsonrpc);
    test_step.dependOn(artifacts.phase0);
    test_step.dependOn(artifacts.phase1);
}
