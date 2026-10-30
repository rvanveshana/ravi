const std = @import("std");
const bytecode = @import("ravi_bytecode");
const Vm = @import("vm.zig").Vm;
const Value = @import("ravi_vm_value").Value;

test "worker failures retain their original runtime error" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .constant, .operand = 0 });
    try chunk.emit(.{ .op = .divide });
    try chunk.emit(.{ .op = .return_value });
    try chunk.functions.append(std.testing.allocator, .{ .entry = 1, .arity = 0, .name = "fail" });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    vm.worker_count = 1;
    const future = try vm.spawnTask(&chunk, 0, &.{});
    try std.testing.expectError(error.DivisionByZero, vm.waitTask(future));
    try std.testing.expectError(error.DivisionByZero, vm.waitTask(future));
}

test "worker boundary rejects parent handles before allocating a scheduler" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.functions.append(std.testing.allocator, .{ .entry = 1, .arity = 1, .name = "identity" });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    const object = try Value.fromHandle(.array, 0);
    try std.testing.expectError(error.UnsupportedTransfer, vm.spawnTask(&chunk, 0, &.{object}));
    try std.testing.expect(vm.task_scheduler == null);
    try std.testing.expectEqual(@as(usize, 0), vm.futures.items.len);
}

test "worker shutdown completes accepted scalar futures" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .return_value });
    try chunk.functions.append(std.testing.allocator, .{ .entry = 1, .arity = 0, .name = "answer" });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    vm.worker_count = 1;
    const future = try vm.spawnTask(&chunk, 0, &.{});
    vm.task_scheduler.?.stop();
    try std.testing.expectEqual(@as(i64, 42), (try vm.waitTask(future)).asInt());
}

test "workers never allocate verifier scratch in the parent chunk allocator" {
    var parent = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var chunk = bytecode.Chunk.init(parent.allocator());
    defer chunk.deinit();
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .return_value });
    try chunk.functions.append(chunk.allocator, .{ .entry = 1, .arity = 0, .name = "answer" });
    // The compiled chunk is read-only from here on. Any attempt to allocate
    // through its arena fails, even while worker scratch allocations succeed.
    parent.fail_index = parent.alloc_index;
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    vm.worker_count = 2;
    var futures: [16]Value = undefined;
    for (&futures) |*future| future.* = try vm.spawnTask(&chunk, 0, &.{});
    for (futures) |future| try std.testing.expectEqual(@as(i64, 42), (try vm.waitTask(future)).asInt());
    try std.testing.expect(!parent.has_induced_failure);
}
