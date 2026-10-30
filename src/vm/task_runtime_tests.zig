const std = @import("std");
const bytecode = @import("ravi_bytecode");
const Value = @import("ravi_vm_value").Value;
const Vm = @import("vm.zig").Vm;
const tasks = @import("tasks.zig");
const Packet = @import("transfer.zig").Packet;
const storage = @import("object_storage.zig");
const collections = @import("ravi_vm_collections");

fn sleepers(chunk: *bytecode.Chunk) !void {
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .constant, .operand = 60000 });
    try chunk.emit(.{ .op = .sleep });
    try chunk.emit(.{ .op = .pop });
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .return_value });
    try chunk.emit(.{ .op = .constant, .operand = 7 });
    try chunk.emit(.{ .op = .return_value });
    _ = try chunk.addFunction(.{ .entry = 1, .arity = 0, .name = "sleeping" });
    _ = try chunk.addFunction(.{ .entry = 6, .arity = 0, .name = "fast" });
}

fn cancelAndClose(vm: *Vm) void {
    if (vm.task_scheduler) |pool| for (vm.futures.items) |entry| if (entry.future) |future| future.requestCancel(pool);
    vm.deinit();
}

test "two thousand parked timers keep one worker available and cancel promptly" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try sleepers(&chunk);
    var vm = try Vm.init(std.testing.allocator);
    defer cancelAndClose(&vm);
    vm.worker_count = 1;
    var handles: [2000]Value = undefined;
    for (&handles) |*handle| handle.* = try vm.spawnTask(&chunk, 0, &.{});
    const fast = try vm.spawnTask(&chunk, 1, &.{});
    const pool = vm.task_scheduler.?;
    const future = try tasks.resolve(&vm, fast);
    try future.ready.waitTimeout(pool.io(), .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } });
    try std.testing.expectEqual(@as(i64, 7), (try vm.waitTask(fast)).asInt());
    const stats = pool.statistics();
    try std.testing.expectEqual(@as(usize, 1), stats.workers);
    try std.testing.expectEqual(@as(usize, 2000), stats.timers);
    for (handles) |handle| try vm.cancelTask(handle);
    for (handles) |handle| try std.testing.expectError(error.Cancelled, vm.waitTask(handle));
    pool.waitIdle();
    try std.testing.expectEqual(@as(usize, 0), pool.statistics().live_tasks);
}

test "nested spawn and wait share a single worker without blocking it" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .make_function, .operand = 1 });
    try chunk.emit(.{ .op = .spawn, .operand = 0 });
    try chunk.emit(.{ .op = .wait });
    try chunk.emit(.{ .op = .return_value });
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .return_value });
    _ = try chunk.addFunction(.{ .entry = 1, .arity = 0, .name = "parent" });
    _ = try chunk.addFunction(.{ .entry = 5, .arity = 0, .name = "child" });
    var vm = try Vm.init(std.testing.allocator);
    defer cancelAndClose(&vm);
    vm.worker_count = 1;
    const handle = try vm.spawnTask(&chunk, 0, &.{});
    const future = try tasks.resolve(&vm, handle);
    try future.ready.waitTimeout(vm.task_scheduler.?.io(), .{ .duration = .{ .clock = .awake, .raw = .fromSeconds(5) } });
    try std.testing.expectEqual(@as(i64, 42), (try vm.waitTask(handle)).asInt());
}

test "immutable program snapshot outlives and ignores source mutation" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    try sleepers(&chunk);
    var vm = try Vm.init(std.testing.allocator);
    defer cancelAndClose(&vm);
    vm.worker_count = 1;
    const handle = try vm.spawnTask(&chunk, 1, &.{});
    chunk.code.items[6].operand = 99;
    chunk.deinit();
    try std.testing.expectEqual(@as(i64, 7), (try vm.waitTask(handle)).asInt());
    try vm.releaseTask(handle);
    try std.testing.expectError(error.InvalidInstruction, vm.waitTask(handle));
}

test "future release reuses storage without reviving a stale handle" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try sleepers(&chunk);
    var vm = try Vm.init(std.testing.allocator);
    defer cancelAndClose(&vm);
    vm.worker_count = 1;
    var stale: Value = Value.nil();
    for (0..5000) |i| {
        const handle = try vm.spawnTask(&chunk, 1, &.{});
        try std.testing.expectEqual(@as(i64, 7), (try vm.waitTask(handle)).asInt());
        if (i == 0) stale = handle;
        try vm.releaseTask(handle);
    }
    try std.testing.expectEqual(@as(usize, 1), vm.futures.items.len);
    try std.testing.expectError(error.InvalidInstruction, vm.waitTask(stale));
}

test "copy transfer preserves cycles aliases strings and isolated mutation" {
    var source = try Vm.init(std.testing.allocator);
    defer source.deinit();
    const slot = try storage.newArray(&source);
    const handle = try Value.fromHandle(.array, slot);
    const text = try @import("state_helpers.zig").internString(&source, "ಕನ್ನಡ");
    try collections.append(source.arrays[slot], handle);
    try collections.append(source.arrays[slot], text);
    const packet = try Packet.create(&source, &.{ handle, handle });
    defer packet.destroy();
    var target = try Vm.init(std.testing.allocator);
    defer target.deinit();
    const values = try packet.restore(&target);
    defer target.allocator.free(values);
    try std.testing.expectEqual(values[0], values[1]);
    const copy = target.arrays[values[0].handleIndex().?];
    try std.testing.expectEqual(values[0], copy.items[0]);
    try std.testing.expectEqualStrings("ಕನ್ನಡ", target.stringSlice(copy.items[1]).?);
    copy.items[0] = Value.fromInt(12);
    try std.testing.expectEqual(handle, source.arrays[slot].items[0]);
}

test "transfer restores roll back injected allocation failures" {
    var source = try Vm.init(std.testing.allocator);
    defer source.deinit();
    const slot = try storage.newArray(&source);
    try collections.append(source.arrays[slot], try @import("state_helpers.zig").internString(&source, "hello"));
    const packet = try Packet.create(&source, &.{try Value.fromHandle(.array, slot)});
    defer packet.destroy();
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var target = try Vm.init(allocator.allocator());
        defer target.deinit();
        allocator.fail_index = allocator.alloc_index + i;
        if (packet.restore(&target)) |values| {
            target.allocator.free(values);
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(@as(usize, 0), target.array_count);
            try std.testing.expectEqual(@as(usize, 0), target.strings.items.len);
            try std.testing.expectEqual(@as(usize, 0), target.gc_roots.items.len);
        }
    }
    try std.testing.expect(i < 40);
}
