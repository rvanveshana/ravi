const std = @import("std");
const bytecode = @import("ravi_bytecode");
const Scheduler = @import("ravi_scheduler").Scheduler;
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const Packet = @import("transfer.zig").Packet;
const Program = @import("task_program.zig").Program;
const Context = @import("task_context.zig").Context;
pub const limit = 4096;
pub const Entry = struct { future: ?*Future = null, generation: u32 = 0 };

pub const Future = struct {
    ready: std.Io.Event = .unset,
    mutex: std.Io.Mutex = .init,
    cancelled: std.atomic.Value(bool) = .init(false),
    context: ?*Context = null,
    waiters: ?*Context = null,
    packet: ?*Packet = null,
    failure: ?Error = null,
    cached: ?Value = null,
    observed: bool = false,

    pub fn complete(self: *Future, pool: *Scheduler, packet: ?*Packet, failure: ?Error) void {
        const io = pool.io();
        self.mutex.lockUncancelable(io);
        self.packet = packet;
        self.failure = failure;
        self.context = null;
        self.ready.set(io);
        var waiter = self.waiters;
        while (waiter) |context| {
            context.wake.store(true, .release);
            waiter = context.next;
        }
        self.waiters = null;
        self.mutex.unlock(io);
        pool.notify();
    }

    pub fn requestCancel(self: *Future, pool: *Scheduler) void {
        const io = pool.io();
        self.mutex.lockUncancelable(io);
        if (!self.ready.isSet()) {
            if (!self.cancelled.swap(true, .acq_rel)) if (self.context) |context| {
                context.wake.store(true, .release);
            };
        }
        self.mutex.unlock(io);
        pool.notify();
    }

    pub fn awaitReady(self: *Future, pool: *Scheduler) void {
        self.ready.waitUncancelable(pool.io());
        // Completion publishes while holding the mutex. Join that critical
        // section before an owner may read or destroy the Future.
        self.mutex.lockUncancelable(pool.io());
        self.mutex.unlock(pool.io());
    }

    pub fn destroy(self: *Future) void {
        if (self.packet) |packet| packet.destroy();
        std.heap.smp_allocator.destroy(self);
    }
};

pub fn resolve(self: anytype, handle: Value) Error!*Future {
    if (handle.handleKind() != .future) return error.TypeGuardFailed;
    const id = handle.handleIndex().?;
    const slot = id % limit;
    if (slot >= self.futures.items.len) return error.InvalidInstruction;
    const entry = self.futures.items[slot];
    if (entry.generation != id / limit) return error.InvalidInstruction;
    return entry.future orelse error.InvalidInstruction;
}

pub fn spawn(self: anytype, chunk: *const bytecode.Chunk, function_index: usize, args: []const Value) Error!Value {
    return spawnCallable(self, chunk, Value.fromHandle(.function, function_index) catch return error.InvalidFunction, args);
}

pub fn spawnCallable(self: anytype, chunk: *const bytecode.Chunk, callee: Value, args: []const Value) Error!Value {
    const index = switch (callee.handleKind() orelse return error.InvalidFunction) {
        .function => callee.handleIndex().?,
        .closure => blk: {
            const slot = callee.handleIndex().?;
            if (slot >= self.closure_count) return error.InvalidFunction;
            break :blk self.closures[slot].function_index;
        },
        else => return error.InvalidFunction,
    };
    if (index >= chunk.functions.items.len) return error.InvalidFunction;
    if (self.task_cancelled) |flag| if (flag.load(.acquire)) return error.Cancelled;
    const owner = std.heap.smp_allocator;
    const inputs = owner.alloc(Value, args.len + 1) catch return error.OutOfMemory;
    defer owner.free(inputs);
    inputs[0] = callee;
    @memcpy(inputs[1..], args);
    const packet = try Packet.create(self, inputs);
    errdefer packet.destroy();
    if (self.task_scheduler == null) self.task_scheduler = Scheduler.initWithCapacity(owner, self.worker_count, limit) catch return error.OutOfMemory;
    const pool = self.task_scheduler.?;
    if (pool.live_tasks.fetchAdd(1, .acq_rel) >= limit) {
        _ = pool.live_tasks.fetchSub(1, .acq_rel);
        return error.TaskLimit;
    }
    errdefer _ = pool.live_tasks.fetchSub(1, .acq_rel);
    if (self.task_program == null) self.task_program = Program.create(chunk) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidInstruction;
    const program = self.task_program.?;
    if (chunk != program.source and chunk != &program.chunk) return error.InvalidFunction;
    var slot: usize = 0;
    while (slot < self.futures.items.len and self.futures.items[slot].future != null) : (slot += 1) {}
    if (slot == limit or self.task_generation == 268435455) return error.TaskLimit;
    if (slot == self.futures.items.len) self.futures.append(self.allocator, .{}) catch return error.OutOfMemory;
    self.task_generation += 1;
    const future = owner.create(Future) catch return error.OutOfMemory;
    errdefer owner.destroy(future);
    future.* = .{};
    const context = owner.create(Context) catch return error.OutOfMemory;
    errdefer owner.destroy(context);
    context.* = .{ .program = program, .function_index = index, .input = packet, .future = future, .pool = pool, .environ = self.environ };
    future.context = context;
    self.futures.items[slot] = .{ .future = future, .generation = self.task_generation };
    errdefer self.futures.items[slot].future = null;
    pool.spawnTask(Context.run, context) catch |err| return if (err == error.QueueFull) error.TaskQueueFull else error.SchedulerStopped;
    return Value.fromHandle(.future, @as(usize, self.task_generation) * limit + slot) catch return error.TaskLimit;
}

pub fn wait(self: anytype, handle: Value) Error!Value {
    const future = try resolve(self, handle);
    return consume(self, future);
}
pub fn consume(self: anytype, future: *Future) Error!Value {
    const pool = self.task_scheduler orelse return error.InvalidInstruction;
    future.awaitReady(pool);
    future.observed = true;
    if (future.cached == null) {
        if (future.packet) |packet| {
            const values = try packet.restore(self);
            defer self.allocator.free(values);
            future.cached = values[0];
            packet.destroy();
            future.packet = null;
        } else future.cached = Value.nil();
    }
    if (future.failure) |failure| {
        if (failure == error.RaisedException) self.last_exception = future.cached.?;
        return failure;
    }
    return future.cached.?;
}

pub fn cancelScope(self: anytype) void {
    if (self.task_scheduler) |pool| for (self.futures.items) |entry| if (entry.future) |future| future.requestCancel(pool);
}

pub fn joinScope(self: anytype) Error!void {
    if (self.task_scheduler) |pool| for (self.futures.items) |entry| if (entry.future) |future| {
        future.awaitReady(pool);
        if (!future.observed and future.failure != null) _ = try consume(self, future);
    };
}

pub fn cancel(self: anytype, handle: Value) Error!void {
    (try resolve(self, handle)).requestCancel(self.task_scheduler orelse return error.InvalidInstruction);
}

pub fn release(self: anytype, handle: Value) Error!void {
    const future = try resolve(self, handle);
    if (!future.ready.isSet()) return error.InvalidInstruction;
    future.awaitReady(self.task_scheduler.?);
    self.futures.items[handle.handleIndex().? % limit].future = null;
    future.destroy();
}

pub fn closeScope(self: anytype) void {
    if (self.task_scheduler) |pool| {
        for (self.futures.items) |entry| if (entry.future) |future| future.awaitReady(pool);
        for (self.futures.items) |entry| if (entry.future) |future| future.destroy();
        self.futures.clearRetainingCapacity();
        if (self.owns_task_scheduler) {
            pool.deinit();
            if (self.task_program) |program| program.destroy();
        }
        self.task_scheduler = null;
        self.task_program = null;
    }
}
