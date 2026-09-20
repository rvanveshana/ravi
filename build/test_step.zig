const std = @import("std");

pub const TestArtifacts = struct {
    lexer: *std.Build.Step,
    parser: *std.Build.Step,
    compiler_vm: []const *std.Build.Step,
    semantic: *std.Build.Step,
    semantic_symbols: *std.Build.Step,
    value: *std.Build.Step,
    vm: *std.Build.Step,
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
    const all = b.step("test", "Run all language and runtime tests");
    inline for (comptime std.meta.fieldNames(TestArtifacts)) |name| {
        const group = b.step(b.fmt("test-{s}", .{name}), b.fmt("Run {s} tests", .{name}));
        const artifact = @field(artifacts, name);
        if (comptime @TypeOf(artifact) == []const *std.Build.Step) {
            for (artifact, 0..) |step, index| {
                group.dependOn(step);
                b.step(b.fmt("test-{s}-{d}", .{ name, index }), "Run one compiler/VM test group").dependOn(step);
            }
        } else group.dependOn(artifact);
        all.dependOn(group);
    }
}
