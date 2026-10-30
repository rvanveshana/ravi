const std = @import("std");
const core = @import("modules_core.zig");

pub const RuntimeModules = struct {
    vm: *std.Build.Module,
    strings: *std.Build.Module,
};

pub fn add(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, modules: core.CoreModules) RuntimeModules {
    const vm = b.createModule(.{ .root_source_file = b.path("src/vm/vm.zig"), .target = target, .optimize = optimize });
    vm.addImport("ravi_scheduler", modules.scheduler);
    vm.addImport("ravi_config", modules.config);
    vm.addImport("ravi_async_state", modules.async_state);
    vm.addImport("ravi_vm_collections", modules.vm_collections);
    vm.addImport("ravi_vm_value", modules.vm_value);
    vm.addImport("ravi_bytecode", modules.bytecode);
    vm.addImport("ravi_debug", modules.debug);
    vm.addImport("ravi_gc", modules.gc);
    vm.addImport("ravi_dispatch", modules.dispatch);
    const strings = b.createModule(.{ .root_source_file = b.path("src/vm/strings.zig"), .target = target, .optimize = optimize });
    return .{ .vm = vm, .strings = strings };
}
