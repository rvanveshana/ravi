const std = @import("std");
const mir = @import("ravi_mir");
const bytecode = @import("ravi_bytecode");
const vm_runtime = @import("ravi_vm");
const emitter = @import("ravi_mir_bytecode_emit");
pub const BlockLabels = struct {
    allocator: std.mem.Allocator,
    offsets: []usize,
    pub fn init(allocator: std.mem.Allocator, function: *const mir.Function) !BlockLabels {
        try function.verify();
        const offsets = try allocator.alloc(usize, function.blocks.items.len);
        errdefer allocator.free(offsets);
        for (function.blocks.items, 0..) |block, index| offsets[index] = block.first_instruction;
        return .{ .allocator = allocator, .offsets = offsets };
    }
    pub fn deinit(self: *BlockLabels) void {
        self.allocator.free(self.offsets);
    }
    pub fn offset(self: *const BlockLabels, block: mir.BlockId) !usize {
        const index = @intFromEnum(block);
        if (index >= self.offsets.len) return error.InvalidBlock;
        return self.offsets[index];
    }
};
pub fn lowerProgram(allocator: anytype, main: *const mir.Function, callables: []const *const mir.Function) !bytecode.Chunk {
    return lowerProgramWithMetadata(allocator, main, callables, &.{}, &.{});
}
pub fn lowerProgramWithMetadata(allocator: anytype, main: *const mir.Function, callables: []const *const mir.Function, classes: []const bytecode.ClassInfo, methods: []const bytecode.MethodInfo) !bytecode.Chunk {
    var chunk = bytecode.Chunk.init(allocator);
    errdefer chunk.deinit();
    try chunk.classes.appendSlice(allocator, classes);
    try chunk.methods.appendSlice(allocator, methods);
    try main.verify();
    for (callables) |function| try function.verify();
    try emitter.emitBody(&chunk, main);
    for (callables) |function| {
        const entry = chunk.code.items.len;
        try emitter.emitBody(&chunk, function);
        _ = try chunk.addFunction(.{
            .entry = entry,
            .arity = function.parameter_count,
            .fixed_count = function.fixed_count,
            .varargs_index = function.varargs_index,
            .kwargs_index = function.kwargs_index,
            .defaults = function.defaults,
            .name = function.name,
            .resumable = function.resumable,
            .suspension_count = function.suspension_count,
            .capture_count = function.capture_count,
        });
    }
    try chunk.verify();
    return chunk;
}
pub fn lower(allocator: anytype, function: *const mir.Function) !bytecode.Chunk {
    var chunk = bytecode.Chunk.init(allocator);
    errdefer chunk.deinit();
    try function.verify();
    try emitter.emitBody(&chunk, function);
    try chunk.verify();
    return chunk;
}
test "MIR block labels preserve verified instruction offsets" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    _ = try source.appendValue(.integer, .{ .constant_integer = 1 }, 1);
    try source.appendEffect(.{ .return_value = @enumFromInt(0) }, 1);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var labels = try BlockLabels.init(std.testing.allocator, &lowered);
    defer labels.deinit();
    try std.testing.expectEqual(@as(usize, 0), try labels.offset(@enumFromInt(0)));
    try std.testing.expectError(error.InvalidBlock, labels.offset(@enumFromInt(1)));
}
test "straight-line MIR lowers to verified bytecode" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    _ = try source.appendValue(.integer, .{ .constant_integer = 2 }, 3);
    _ = try source.appendValue(.integer, .{ .constant_integer = 3 }, 3);
    _ = try source.appendValue(.integer, .{ .binary = .{ .operator = .add, .left = @enumFromInt(0), .right = @enumFromInt(1) } }, 3);
    try source.appendEffect(.{ .return_value = @enumFromInt(2) }, 3);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var found_add = false;
    for (chunk.code.items) |instruction| {
        if (instruction.op == .add) found_add = true;
    }
    try std.testing.expect(found_add);
}
test "lowered MIR executes through the production VM" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    _ = try source.appendValue(.integer, .{ .constant_integer = 20 }, 4);
    _ = try source.appendValue(.integer, .{ .constant_integer = 22 }, 4);
    _ = try source.appendValue(.integer, .{ .binary = .{ .operator = .add, .left = @enumFromInt(0), .right = @enumFromInt(1) } }, 4);
    try source.appendEffect(.{ .return_value = @enumFromInt(2) }, 4);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(i64, 42), result.asInt());
}
test "MIR phi edges select the incoming value" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "phi");
    defer source.deinit();
    const left = try source.appendValue(.integer, .{ .constant_integer = 10 }, 1);
    const right = try source.appendValue(.integer, .{ .constant_integer = 20 }, 1);
    const condition = try source.appendValue(.boolean, .{ .binary = .{ .operator = .equal, .left = left, .right = left } }, 1);
    try source.appendEffect(.{ .branch = .{ .condition = condition, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } }, 1);
    try source.appendEffect(.{ .jump = @enumFromInt(3) }, 1);
    try source.appendEffect(.{ .jump = @enumFromInt(3) }, 1);
    const inputs = try std.testing.allocator.alloc(@import("ravi_hir").PhiInput, 2);
    inputs[0] = .{ .block = @enumFromInt(1), .value = left };
    inputs[1] = .{ .block = @enumFromInt(2), .value = right };
    const merged = try source.appendValue(.integer, .{ .phi = inputs }, 1);
    try source.appendEffect(.{ .return_value = merged }, 1);
    try source.setBlocks(&.{
        .{ .first_instruction = 0, .instruction_count = 4 },
        .{ .first_instruction = 4, .instruction_count = 1 },
        .{ .first_instruction = 5, .instruction_count = 1 },
        .{ .first_instruction = 6, .instruction_count = 2 },
    });
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const result = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(i64, 10), result.asInt());
}
test "multi-function MIR lowering emits callable entries and executes calls" {
    var main_source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer main_source.deinit();
    const argument = try main_source.appendValue(.integer, .{ .constant_integer = 21 }, 1);
    const result = try main_source.appendValue(.integer, .{ .call = .{ .function = 0, .arguments = &[_]@import("ravi_hir").ValueId{argument} } }, 1);
    try main_source.appendEffect(.{ .return_value = result }, 1);
    var function_source = @import("ravi_hir").Function.init(std.testing.allocator, "double");
    defer function_source.deinit();
    function_source.parameter_count = 1;
    const parameter = try function_source.appendValue(.integer, .{ .parameter = 0 }, 1);
    const factor = try function_source.appendValue(.integer, .{ .constant_integer = 2 }, 1);
    const doubled = try function_source.appendValue(.integer, .{ .binary = .{ .operator = .multiply, .left = parameter, .right = factor } }, 1);
    try function_source.appendEffect(.{ .return_value = doubled }, 1);
    var main = try mir.Function.lower(std.testing.allocator, &main_source);
    defer main.deinit();
    var function = try mir.Function.lower(std.testing.allocator, &function_source);
    defer function.deinit();
    var callables = [_]*const mir.Function{&function};
    var chunk = try lowerProgram(std.testing.allocator, &main, &callables);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 1), chunk.functions.items.len);
    try std.testing.expectEqual(@as(usize, 1), chunk.functions.items[0].arity);
    try std.testing.expect(chunk.functions.items[0].entry > 0);
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    const value = try vm.runValue(&chunk);
    try std.testing.expectEqual(@as(i64, 42), value.asInt());
}
test "MIR closure captures a value and executes through the VM" {
    var main_source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer main_source.deinit();
    const captured = try main_source.appendValue(.integer, .{ .constant_integer = 41 }, 1);
    const closure = try main_source.appendValue(.dynamic, .{ .make_closure = .{ .function = 0, .captures = &[_]@import("ravi_hir").ValueId{captured} } }, 1);
    const result = try main_source.appendValue(.dynamic, .{ .call_value = .{ .callee = closure, .arguments = &.{} } }, 1);
    try main_source.appendEffect(.{ .return_value = result }, 1);
    var closure_source = @import("ravi_hir").Function.init(std.testing.allocator, "captured");
    defer closure_source.deinit();
    closure_source.capture_count = 1;
    const value = try closure_source.appendValue(.dynamic, .{ .load_capture = 0 }, 1);
    try closure_source.appendEffect(.{ .return_value = value }, 1);
    var main = try mir.Function.lower(std.testing.allocator, &main_source);
    defer main.deinit();
    var function = try mir.Function.lower(std.testing.allocator, &closure_source);
    defer function.deinit();
    var callables = [_]*const mir.Function{&function};
    var chunk = try lowerProgram(std.testing.allocator, &main, &callables);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 1), chunk.functions.items[0].capture_count);
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 41), (try vm.runValue(&chunk)).asInt());
}
test "MIR indexed mutation updates an array through the VM" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const original = try source.appendValue(.integer, .{ .constant_integer = 1 }, 1);
    const replacement = try source.appendValue(.integer, .{ .constant_integer = 9 }, 1);
    const array = try source.appendValue(.dynamic, .{ .make_array = &[_]@import("ravi_hir").ValueId{original} }, 1);
    const key = try source.appendValue(.integer, .{ .constant_integer = 0 }, 1);
    try source.appendEffect(.{ .store_index = .{ .object = array, .key = key, .value = replacement } }, 1);
    const result = try source.appendValue(.dynamic, .{ .index = .{ .object = array, .key = key } }, 1);
    try source.appendEffect(.{ .return_value = result }, 1);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 9), (try vm.runValue(&chunk)).asInt());
}
test "MIR bytecode lowering materializes conditional CFG blocks" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    function.value_count = 3;
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(0), .result_type = .boolean, .operation = .{ .constant_integer = 1 } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .branch = .{ .condition = @enumFromInt(0), .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } } });
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(1), .result_type = .integer, .operation = .{ .constant_integer = 42 } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .return_value = @enumFromInt(1) } });
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(2), .result_type = .integer, .operation = .{ .constant_integer = 7 } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .return_value = @enumFromInt(2) } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 2 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 2, .instruction_count = 2 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 4, .instruction_count = 2 });
    var chunk = try lower(std.testing.allocator, &function);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 42), (try vm.runValue(&chunk)).asInt());
}
test "HIR CFG survives MIR lowering and executes" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "branch");
    defer source.deinit();
    const condition = try source.appendValue(.boolean, .{ .constant_integer = 1 }, 1);
    try source.appendEffect(.{ .branch = .{ .condition = condition, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } }, 1);
    const selected = try source.appendValue(.integer, .{ .constant_integer = 42 }, 2);
    try source.appendEffect(.{ .return_value = selected }, 2);
    const other = try source.appendValue(.integer, .{ .constant_integer = 7 }, 3);
    try source.appendEffect(.{ .return_value = other }, 3);
    try source.setBlocks(&[_]@import("ravi_hir").Block{
        .{ .first_instruction = 0, .instruction_count = 2 },
        .{ .first_instruction = 2, .instruction_count = 2 },
        .{ .first_instruction = 4, .instruction_count = 2 },
    });
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    var vm = try vm_runtime.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 42), (try vm.runValue(&chunk)).asInt());
}
test "MIR verifier rejects a value from a non-dominating branch" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    function.value_count = 2;
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(0), .result_type = .boolean, .operation = .{ .constant_integer = 1 } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .branch = .{ .condition = @enumFromInt(0), .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } } });
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(1), .result_type = .integer, .operation = .{ .constant_integer = 42 } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .jump = @enumFromInt(3) } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .return_value = @enumFromInt(1) } });
    try function.instructions.append(std.testing.allocator, .{ .operation = .{ .return_value = @enumFromInt(1) } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 2 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 2, .instruction_count = 2 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 4, .instruction_count = 1 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 5, .instruction_count = 1 });
    try std.testing.expectError(error.UndefinedValue, function.verify());
}
test "MIR lowering preserves suspension markers" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "async_main");
    defer source.deinit();
    source.resumable = true;
    source.suspension_count = 1;
    try source.appendEffect(.{ .suspend_point = .{ .resume_line = 12 } }, 12);
    var lowered = try mir.Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    var chunk = try lower(std.testing.allocator, &lowered);
    defer chunk.deinit();
    try std.testing.expectEqual(bytecode.OpCode.suspend_point, chunk.code.items[0].op);
    try std.testing.expectEqual(@as(i64, 12), chunk.code.items[0].operand);
}
test "MIR lowering rejects inconsistent suspension metadata" {
    var source = @import("ravi_hir").Function.init(std.testing.allocator, "broken_async");
    defer source.deinit();
    source.resumable = true;
    source.suspension_count = 2;
    try source.appendEffect(.{ .suspend_point = .{ .resume_line = 4 } }, 4);
    var lowered = mir.Function.lower(std.testing.allocator, &source) catch |err| {
        try std.testing.expectEqual(error.InvalidResumableMetadata, err);
        return;
    };
    defer lowered.deinit();
    try std.testing.expectError(error.InvalidResumableMetadata, lowered.verify());
}
