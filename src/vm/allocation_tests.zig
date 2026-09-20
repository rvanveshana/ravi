const std = @import("std");
const Vm = @import("vm.zig").Vm;
const storage = @import("object_storage.zig");
const state = @import("state_helpers.zig");
const Value = @import("ravi_vm_value").Value;

fn constructObjects(allocator: std.mem.Allocator) !void {
    var vm = try Vm.init(allocator);
    defer vm.deinit();
    _ = try storage.newArray(&vm);
    _ = try storage.newDict(&vm);
    _ = try storage.newClosure(&vm, 0, 2);
    _ = try storage.newCell(&vm, Value.nil());
    _ = try storage.newInstance(&vm, 0);
    _ = try storage.newException(&vm, "RuntimeError");
    _ = try state.internString(&vm, "owned payload");
}

test "object construction rolls back every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, constructObjects, .{});
}
