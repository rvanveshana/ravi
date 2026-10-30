const std = @import("std");
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const tasks = @import("tasks.zig");

pub fn deadline(vm: anytype, io: std.Io, ip: usize, duration: Value) Error!i96 {
    if (!duration.isInt() or duration.asInt() < 0) return error.TypeGuardFailed;
    if (vm.task_timeout_deadline == null or vm.task_timeout_ip != ip) {
        vm.task_timeout_deadline = std.Io.Clock.now(.awake, io).nanoseconds + @as(i96, duration.asInt()) * std.time.ns_per_ms;
        vm.task_timeout_ip = ip;
    }
    return vm.task_timeout_deadline.?;
}

pub fn waitTimeout(vm: anytype, args: []const Value, ip: usize) Error!?Value {
    const future = try tasks.resolve(vm, args[0]);
    const io = vm.task_scheduler.?.io();
    const until = try deadline(vm, io, ip, args[1]);
    if (future.ready.isSet()) {
        vm.task_timeout_deadline = null;
        return try tasks.consume(vm, future);
    }
    if (std.Io.Clock.now(.awake, io).nanoseconds >= until) {
        vm.task_timeout_deadline = null;
        return error.TimedOut;
    }
    if (vm.cooperative) {
        vm.task_waiting = future;
        vm.task_deadline = until;
        return null;
    }
    future.ready.waitTimeout(io, .{ .deadline = .{ .clock = .awake, .raw = .{ .nanoseconds = until } } }) catch |err| {
        vm.task_timeout_deadline = null;
        return if (err == error.Timeout) error.TimedOut else error.Cancelled;
    };
    vm.task_timeout_deadline = null;
    return try tasks.consume(vm, future);
}

pub fn poll(self: anytype, ip: *usize, next_ip: ?*usize, quantum: *usize) Error!bool {
    if (self.task_cancelled) |flag| if (!self.task_cancel_injected and flag.load(.acquire)) {
        self.task_cancel_injected = true;
        if (!@import("state_helpers.zig").handleFaultWithError(self, ip, error.Cancelled)) return error.Cancelled;
        ip.* += 1;
    };
    if (quantum.* == 4096) {
        (next_ip orelse return error.InvalidInstruction).* = ip.*;
        return true;
    }
    quantum.* += 1;
    return false;
}

pub fn sleep(self: anytype, ip: usize, next_ip: ?*usize) Error!bool {
    if (self.stack_top == 0) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    if (!value.isInt() or value.asInt() < 0) return error.TypeGuardFailed;
    const milliseconds: u64 = @intCast(value.asInt());
    if (self.cooperative and milliseconds != 0) {
        const pool = self.task_scheduler orelse return error.InvalidInstruction;
        self.task_deadline = std.Io.Clock.now(.awake, pool.io()).nanoseconds + @as(i96, milliseconds) * std.time.ns_per_ms;
        (next_ip orelse return error.InvalidInstruction).* = ip + 1;
        self.stack[self.stack_top - 1] = Value.nil();
        return true;
    }
    try @import("sleep.zig").sleepMilliseconds(milliseconds);
    self.stack[self.stack_top - 1] = Value.nil();
    return false;
}

pub fn wait(self: anytype, ip: usize, next_ip: ?*usize) Error!bool {
    if (self.stack_top == 0) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const future = try tasks.resolve(self, value);
    if (self.cooperative and !future.ready.isSet()) {
        self.task_waiting = future;
        (next_ip orelse return error.InvalidInstruction).* = ip;
        return true;
    }
    self.stack[self.stack_top - 1] = try tasks.wait(self, value);
    return false;
}
