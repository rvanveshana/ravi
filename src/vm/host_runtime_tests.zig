const std = @import("std");
const Vm = @import("vm.zig").Vm;
const Value = @import("ravi_vm_value").Value;
const host = @import("host_calls.zig");
const state = @import("state_helpers.zig");
const storage = @import("object_storage.zig");
const collections = @import("ravi_vm_collections");
const json = @import("json_runtime.zig");

test "JSON rejects duplicate keys cycles invalid UTF8 and integer overflow" {
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.JsonError, json.decode(&vm, "{\"x\":1,\"x\":2}"));
    try std.testing.expectError(error.InvalidUtf8, json.decode(&vm, "\"\xff\""));
    try std.testing.expectError(error.IntegerOutOfRange, json.decode(&vm, "140737488355328"));
    const slot = try storage.newArray(&vm);
    const value = try Value.fromHandle(.array, slot);
    try collections.append(vm.arrays[slot], value);
    try std.testing.expectError(error.JsonError, json.encode(&vm, value));
    try std.testing.expectError(error.JsonError, json.encode(&vm, Value.fromFloat(std.math.inf(f64))));
}

test "UTF8 byte conversion validates bytes and preserves Kannada" {
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    const text = try state.internString(&vm, "ಕನ್ನಡ");
    const bytes = try host.perform(&vm, .bytes_encode, &.{text});
    const restored = try host.perform(&vm, .bytes_decode, &.{bytes});
    try std.testing.expectEqualStrings("ಕನ್ನಡ", vm.stringSlice(restored).?);
    vm.arrays[bytes.handleIndex().?].items[0] = Value.fromInt(256);
    try std.testing.expectError(error.TypeGuardFailed, host.perform(&vm, .bytes_decode, &.{bytes}));
    vm.arrays[bytes.handleIndex().?].items[0] = Value.fromInt(255);
    try std.testing.expectError(error.InvalidUtf8, host.perform(&vm, .bytes_decode, &.{bytes}));
}

test "channel deadlines close drain and null messages have distinct outcomes" {
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    const channel = try host.perform(&vm, .channel_create, &.{Value.fromInt(1)});
    try std.testing.expectError(error.TimedOut, host.perform(&vm, .channel_recv_timeout, &.{ channel, Value.fromInt(1) }));
    _ = try host.perform(&vm, .channel_send, &.{ channel, Value.nil() });
    try std.testing.expectError(error.TimedOut, host.perform(&vm, .channel_send_timeout, &.{ channel, Value.fromInt(1), Value.fromInt(1) }));
    _ = try host.perform(&vm, .channel_close, &.{channel});
    try std.testing.expect((try host.perform(&vm, .channel_recv, &.{channel})).isNil());
    try std.testing.expectError(error.ChannelClosed, host.perform(&vm, .channel_recv, &.{channel}));
    try std.testing.expectError(error.ChannelClosed, host.perform(&vm, .channel_send, &.{ channel, Value.nil() }));
}

test "channel messages reject channel identities to avoid reference cycles" {
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    const channel = try host.perform(&vm, .channel_create, &.{Value.fromInt(1)});
    try std.testing.expectError(error.UnsupportedTransfer, host.perform(&vm, .channel_send, &.{ channel, channel }));
}

test "JSON decoder rolls back allocations on OOM" {
    var i: usize = 0;
    while (i < 80) : (i += 1) {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var vm = try Vm.init(allocator.allocator());
        defer vm.deinit();
        allocator.fail_index = allocator.alloc_index + i;
        if (json.decode(&vm, "{\"name\":\"ಕನ್ನಡ\",\"list\":[1,2]}")) |_| break else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(@as(usize, 0), vm.dict_count);
            try std.testing.expectEqual(@as(usize, 0), vm.array_count);
            try std.testing.expectEqual(@as(usize, 0), vm.strings.items.len);
        }
    }
    try std.testing.expect(i < 80);
}
