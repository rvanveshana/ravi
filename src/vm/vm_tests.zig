const std = @import("std");
const bytecode = @import("ravi_bytecode");
const debug = @import("ravi_debug");
const async_state = @import("ravi_async_state");
const Vm = @import("vm.zig").Vm;

test "VM debugger attachment pauses at instruction breakpoints" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .halt });
    var debugger = debug.Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    _ = try debugger.addBreakpoint(0);
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    vm.attachDebugger(&debugger);
    try std.testing.expectError(error.DebuggerPaused, vm.runValue(&chunk));
    vm.detachDebugger();
    _ = try vm.runValue(&chunk);
}

test "VM resumable execution yields and resumes at the next instruction" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 7 });
    try chunk.emit(.{ .op = .suspend_point, .operand = 12 });
    try chunk.emit(.{ .op = .return_value });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    switch (try vm.runResumable(&chunk)) {
        .suspended => |value| try std.testing.expectEqual(@as(i64, 7), value.asInt()),
        .completed => return error.TestExpectedEqual,
    }
    try std.testing.expectEqual(async_state.Status.suspended, vm.resumableStatus().?);
    switch (try vm.resumeResumable()) {
        .suspended => return error.TestExpectedEqual,
        .completed => |value| try std.testing.expectEqual(@as(i64, 7), value.asInt()),
    }
    try std.testing.expectEqual(async_state.Status.completed, vm.resumableStatus().?);
}

test "VM interning scales beyond the legacy thousand-string cap" {
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    var buffer: [32]u8 = undefined;
    for (0..1_024) |index| {
        const text = try std.fmt.bufPrint(&buffer, "string-{d}", .{index});
        _ = try @import("state_helpers.zig").internString(&vm, text);
    }
    try std.testing.expect(vm.strings.items.len >= 1_024);
}

test "VM preserves the active exception when a handler rethrows" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .try_begin, .operand = 4 });
    try chunk.emit(.{ .op = .raise_value });
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .raise_value });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.RaisedException, vm.runValue(&chunk));
    try std.testing.expect(vm.last_exception.isInt());
    try std.testing.expectEqual(@as(i64, 42), vm.last_exception.asInt());
}
