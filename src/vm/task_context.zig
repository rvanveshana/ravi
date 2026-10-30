const std = @import("std");
const Vm = @import("vm.zig").Vm;
const tasks = @import("tasks.zig");
const Scheduler = @import("ravi_scheduler").Scheduler;
const Packet = @import("transfer.zig").Packet;
const Program = @import("task_program.zig").Program;
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const execution = @import("execution.zig");

pub const Context = struct {
    program: *Program,
    function_index: usize,
    input: ?*Packet,
    future: *tasks.Future,
    pool: *Scheduler,
    child: ?*Vm = null,
    wake: std.atomic.Value(bool) = .init(false),
    next: ?*Context = null,
    waiting_on: ?*tasks.Future = null,
    channel_waiting: ?*@import("shared_channel.zig").Shared = null,
    finished: bool = false,
    result: Error!Value = Value.nil(),
    environ: std.process.Environ = .empty,

    pub fn run(raw: ?*anyopaque) void {
        const self: *Context = @ptrCast(@alignCast(raw.?));
        self.detach();
        self.wake.store(false, .release);
        self.step() catch |err| {
            self.result = err;
            self.finished = true;
        };
        if (self.finished) {
            if (self.child) |child| {
                const failed = if (self.result) |_| false else |_| true;
                if (child.pending_io) |future| if (!future.ready.isSet()) {
                    self.park(future, std.math.maxInt(i96));
                    return;
                };
                for (child.futures.items, 0..) |entry, slot| if (entry.future) |future| {
                    if (failed or self.future.cancelled.load(.acquire)) future.requestCancel(self.pool);
                    if (!future.ready.isSet()) {
                        self.park(future, std.math.maxInt(i96));
                        return;
                    }
                    if (!future.observed and future.failure != null) {
                        if (self.result) |_| {
                            self.result = tasks.wait(child, Value.fromHandle(.future, @as(usize, entry.generation) * tasks.limit + slot) catch unreachable);
                        } else |_| {}
                    }
                };
            }
            var packet: ?*Packet = null;
            var failure: ?Error = null;
            if (self.result) |result| {
                if (self.child) |child| packet = capture(child, result, &failure);
            } else |err| {
                failure = err;
                if (err == error.RaisedException) if (self.child) |child| {
                    packet = capture(child, child.last_exception, &failure);
                };
            }
            if (self.input) |input| input.destroy();
            if (self.child) |child| {
                child.deinit();
                std.heap.smp_allocator.destroy(child);
            }
            _ = self.pool.live_tasks.fetchSub(1, .acq_rel);
            self.future.complete(self.pool, packet, failure);
            std.heap.smp_allocator.destroy(self);
            return;
        }
        const child = self.child.?;
        if (child.task_channel) |channel| {
            channel.lock();
            if (!channel.available(child.task_channel_send)) {
                self.next = channel.waiters;
                channel.waiters = self;
                self.channel_waiting = channel;
            } else self.wake.store(true, .release);
            channel.unlock();
            self.park(null, child.task_deadline orelse std.math.maxInt(i96));
        } else if (child.task_waiting) |future| self.park(future, child.task_deadline orelse std.math.maxInt(i96)) else self.park(null, child.task_deadline orelse 0);
    }

    fn step(self: *Context) Error!void {
        if (self.child == null and self.future.cancelled.load(.acquire)) return error.Cancelled;
        if (self.finished) return;
        if (self.child == null) {
            const child = std.heap.smp_allocator.create(Vm) catch return error.OutOfMemory;
            child.* = Vm.init(std.heap.smp_allocator) catch |err| {
                std.heap.smp_allocator.destroy(child);
                return err;
            };
            self.child = child;
            child.task_scheduler = self.pool;
            child.owns_task_scheduler = false;
            child.task_program = self.program;
            child.cooperative = true;
            child.task_cancelled = &self.future.cancelled;
            child.host_io = self.pool.io();
            child.environ = self.environ;
            const values = try self.input.?.restore(child);
            defer child.allocator.free(values);
            try @import("task_execution.zig").initialize(child, &self.program.chunk, self.function_index, values[1..]);
            if (values[0].handleKind() == .closure) child.frames[1].captures = child.closures[values[0].handleIndex().?].captures;
            self.input.?.destroy();
            self.input = null;
        }
        const child = self.child.?;
        child.task_waiting = null;
        child.task_deadline = null;
        child.task_channel = null;
        switch (try execution.executeInternal(child, &self.program.chunk, null, child.task_ip, &child.task_ip, false)) {
            .completed => |value| {
                self.result = value;
                self.finished = true;
            },
            .suspended => {},
        }
    }

    fn capture(child: *Vm, value: Value, failure: *?Error) ?*Packet {
        return Packet.create(child, &.{value}) catch |err| {
            failure.* = err;
            return null;
        };
    }

    fn park(self: *Context, future: ?*tasks.Future, deadline: i96) void {
        if (future) |target| {
            target.mutex.lockUncancelable(self.pool.io());
            if (!target.ready.isSet()) {
                self.next = target.waiters;
                target.waiters = self;
                self.waiting_on = target;
            } else self.wake.store(true, .release);
            target.mutex.unlock(self.pool.io());
        }
        if (self.future.cancelled.load(.acquire) and (self.child == null or !self.child.?.task_cancel_injected)) self.wake.store(true, .release);
        self.pool.scheduleAt(deadline, run, self, &self.wake) catch {
            self.pool.resumeTask(run, self) catch unreachable;
        };
    }

    fn detach(self: *Context) void {
        if (self.channel_waiting) |channel| {
            channel.lock();
            var link = &channel.waiters;
            while (link.*) |waiter| {
                if (waiter == self) {
                    link.* = self.next;
                    break;
                }
                link = &waiter.next;
            }
            channel.unlock();
            self.channel_waiting = null;
            self.next = null;
        }
        if (self.waiting_on) |target| {
            target.mutex.lockUncancelable(self.pool.io());
            var link = &target.waiters;
            while (link.*) |waiter| {
                if (waiter == self) {
                    link.* = self.next;
                    break;
                }
                link = &waiter.next;
            }
            target.mutex.unlock(self.pool.io());
            self.waiting_on = null;
            self.next = null;
        }
    }
};
