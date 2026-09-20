const std = @import("std");

pub const Future = @import("future.zig").Future;
pub const AwaitStatus = @import("future.zig").AwaitStatus;
pub const AwaitResult = @import("future.zig").AwaitResult;
pub const Channel = @import("channel.zig").Channel;
pub const ReceiveResult = @import("channel.zig").ReceiveResult;
pub const TaskFn = *const fn (?*anyopaque) void;
pub const Task = struct { func: TaskFn, ctx: ?*anyopaque };

/// Bounded worker pool. Accepted tasks drain before shutdown completes.
/// Call stop/deinit from the owner, never from one of this pool's tasks.
/// The owner must join concurrent API users before deinit frees the pool.
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    backend: std.Io.Threaded,
    threads: []std.Thread,
    queue: []Task,
    head: usize = 0,
    queued: usize = 0,
    active: usize = 0,
    accepting: bool = true,
    mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    stopped: std.Io.Event = .unset,

    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !*Scheduler {
        const count = if (thread_count == 0) try std.Thread.getCpuCount() else thread_count;
        if (count == 0) return error.InvalidThreadCount;
        const capacity = try std.math.mul(usize, count, 64);
        const self = try allocator.create(Scheduler);
        errdefer allocator.destroy(self);
        const threads = try allocator.alloc(std.Thread, count);
        errdefer allocator.free(threads);
        const queue = try allocator.alloc(Task, capacity);
        errdefer allocator.free(queue);
        self.* = .{
            .allocator = allocator,
            .backend = std.Io.Threaded.init(std.heap.smp_allocator, .{}),
            .threads = threads,
            .queue = queue,
        };
        errdefer self.backend.deinit();
        var started: usize = 0;
        errdefer {
            const runtime_io = self.io();
            self.mutex.lockUncancelable(runtime_io);
            self.accepting = false;
            self.changed.broadcast(runtime_io);
            self.mutex.unlock(runtime_io);
            for (threads[0..started]) |thread| thread.join();
        }
        while (started < count) : (started += 1)
            threads[started] = try std.Thread.spawn(.{}, workerLoop, .{self});
        return self;
    }

    pub fn io(self: *Scheduler) std.Io {
        return self.backend.io();
    }

    fn workerLoop(self: *Scheduler) void {
        const runtime_io = self.io();
        self.mutex.lockUncancelable(runtime_io);
        defer self.mutex.unlock(runtime_io);
        while (true) {
            while (self.queued == 0 and self.accepting)
                self.changed.waitUncancelable(runtime_io, &self.mutex);
            if (self.queued == 0) return;
            const task = self.queue[self.head];
            self.head = (self.head + 1) % self.queue.len;
            self.queued -= 1;
            self.active += 1;
            self.mutex.unlock(runtime_io);
            task.func(task.ctx);
            self.mutex.lockUncancelable(runtime_io);
            self.active -= 1;
            if (self.queued == 0 and self.active == 0) self.changed.broadcast(runtime_io);
        }
    }

    pub fn spawnTask(self: *Scheduler, func: TaskFn, ctx: ?*anyopaque) !void {
        const runtime_io = self.io();
        self.mutex.lockUncancelable(runtime_io);
        defer self.mutex.unlock(runtime_io);
        if (!self.accepting) return error.SchedulerStopped;
        if (self.queued == self.queue.len) return error.QueueFull;
        self.queue[(self.head + self.queued) % self.queue.len] = .{ .func = func, .ctx = ctx };
        self.queued += 1;
        self.changed.broadcast(runtime_io);
    }

    /// Waits for a quiescent instant. Producers may submit again afterwards.
    pub fn waitIdle(self: *Scheduler) void {
        const runtime_io = self.io();
        self.mutex.lockUncancelable(runtime_io);
        defer self.mutex.unlock(runtime_io);
        while (self.queued != 0 or self.active != 0)
            self.changed.waitUncancelable(runtime_io, &self.mutex);
    }

    pub fn stop(self: *Scheduler) void {
        const runtime_io = self.io();
        self.mutex.lockUncancelable(runtime_io);
        if (!self.accepting) {
            self.mutex.unlock(runtime_io);
            self.stopped.waitUncancelable(runtime_io);
            return;
        }
        self.accepting = false;
        self.changed.broadcast(runtime_io);
        self.mutex.unlock(runtime_io);
        for (self.threads) |thread| thread.join();
        self.stopped.set(runtime_io);
    }

    pub fn deinit(self: *Scheduler) void {
        self.stop();
        self.backend.deinit();
        self.allocator.free(self.queue);
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }
};

test {
    _ = @import("scheduler_tests.zig");
}
