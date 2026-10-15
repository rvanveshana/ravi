const std = @import("std");
const core = @import("build/modules_core.zig");
const runtime = @import("build/modules_runtime.zig");
const compiler = @import("build/modules_compiler.zig");
const language = @import("build/modules_language.zig");
const artifacts_tests = @import("build/artifacts_tests.zig");
const test_step = @import("build/test_step.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core_modules = core.add(b, target, optimize);
    const runtime_modules = runtime.add(b, target, optimize, core_modules);
    const compiler_modules = compiler.add(b, target, optimize, core_modules, runtime_modules);
    const language_modules = language.add(b, target, optimize, core_modules);
    compiler_modules.pipeline.addImport("ravi_parser", language_modules.parser);

    const root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    language.addRootImports(root_module, core_modules, runtime_modules, compiler_modules, language_modules);

    const exe = b.addExecutable(.{ .name = "ravi", .root_module = root_module });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Tokenize the sample Ravi program").dependOn(&run.step);

    const tests: test_step.TestArtifacts = artifacts_tests.add(b, target, optimize, core_modules, runtime_modules, compiler_modules, language_modules);
    test_step.addTestStep(b, tests);
}
