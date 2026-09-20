const std = @import("std");
const bytecode = @import("ravi_bytecode");
const scheduler = @import("ravi_scheduler");
const Value = @import("ravi_vm_value").Value;
const RuntimeError = @import("errors.zig").RuntimeError;
const execution = @import("task_execution.zig");

pub const Future = struct {
    ready: std.Io.Event = .unset,
    result: RuntimeError!Value = Value.nil(),

    fn complete(self: *Future, io: std.Io, result: RuntimeError!Value) void {
        self.result = result;
        self.ready.set(io);
    }

    fn await(self: *Future, io: std.Io) RuntimeError!Value {
        self.ready.waitUncancelable(io);
        return self.result;
    }
};

const Context = struct {
    chunk: *const bytecode.Chunk,
    function_index: usize,
    args: []Value,
    future: *Future,
    io: std.Io,

    fn run(context: ?*anyopaque) void {
        const task: *Context = @ptrCast(@alignCast(context.?));
        // Parent compiler/VM allocators may be arenas and are not shared with workers.
        const allocator = std.heap.smp_allocator;
        defer allocator.destroy(task);
        defer allocator.free(task.args);
        var child = @import("vm.zig").Vm.init(allocator) catch {
            task.future.complete(task.io, error.OutOfMemory);
            return;
        };
        defer child.deinit();
        const result = execution.executeFunction(&child, task.chunk, task.function_index, task.args);
        task.future.complete(task.io, if (result) |value|
            if (value.isHandle()) error.UnsupportedTransfer else value
        else |err|
            err);
    }
};

pub fn spawn(self: anytype, chunk: *const bytecode.Chunk, function_index: usize, args: []const Value) RuntimeError!Value {
    if (function_index >= chunk.functions.items.len) return error.InvalidFunction;
    // Until object transfer is implemented, reject parent-heap handles before
    // submission. Reinterpreting a parent's table index in a child is invalid.
    for (args) |argument| if (argument.isHandle()) return error.UnsupportedTransfer;
    if (self.task_scheduler == null)
        self.task_scheduler = scheduler.Scheduler.init(self.allocator, self.worker_count) catch return error.OutOfMemory;
    const pool = self.task_scheduler.?;
    const future = self.allocator.create(Future) catch return error.OutOfMemory;
    errdefer self.allocator.destroy(future);
    future.* = .{};
    const allocator = std.heap.smp_allocator;
    const owned_args = allocator.dupe(Value, args) catch return error.OutOfMemory;
    errdefer allocator.free(owned_args);
    const context = allocator.create(Context) catch return error.OutOfMemory;
    errdefer allocator.destroy(context);
    context.* = .{ .chunk = chunk, .function_index = function_index, .args = owned_args, .future = future, .io = pool.io() };
    const handle = Value.fromHandle(.future, self.futures.items.len) catch return error.OutOfMemory;
    self.futures.append(self.allocator, future) catch return error.OutOfMemory;
    errdefer _ = self.futures.pop();
    pool.spawnTask(Context.run, context) catch |err| return switch (err) {
        error.QueueFull => error.TaskQueueFull,
        error.SchedulerStopped => error.SchedulerStopped,
    };
    return handle;
}

pub fn wait(self: anytype, handle: Value) RuntimeError!Value {
    if (handle.handleKind() != .future) return error.TypeGuardFailed;
    const index = handle.handleIndex() orelse return error.InvalidInstruction;
    if (index >= self.futures.items.len) return error.InvalidInstruction;
    const pool = self.task_scheduler orelse return error.InvalidInstruction;
    return self.futures.items[index].await(pool.io());
}
