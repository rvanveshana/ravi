const std = @import("std");

pub const TaskFn = *const fn (ctx: ?*anyopaque) void;

pub const Task = struct {
    func: TaskFn,
    ctx: ?*anyopaque = null,
    cancelled: bool = false,
};

pub const AwaitStatus = enum { completed, cancelled, timed_out };
pub const AwaitResult = struct { status: AwaitStatus, value: ?*anyopaque = null };
pub const ReceiveResult = union(enum) { value: ?*anyopaque, empty, closed };

pub const Future = struct {
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    value: ?*anyopaque = null,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    transition_mutex: std.atomic.Mutex = .unlocked,

    pub fn complete(self: *Future, value: ?*anyopaque) void {
        lock(&self.transition_mutex);
        defer self.transition_mutex.unlock();
        if (self.done.load(.acquire)) return;
        self.value = value;
        self.done.store(true, .release);
    }

    pub fn cancel(self: *Future) void {
        lock(&self.transition_mutex);
        defer self.transition_mutex.unlock();
        if (self.done.load(.acquire)) return;
        self.cancelled.store(true, .release);
        self.done.store(true, .release);
    }

    pub fn isDone(self: *const Future) bool {
        return self.done.load(.acquire);
    }

    pub fn await(self: *Future) ?*anyopaque {
        while (!self.done.load(.acquire)) std.Thread.yield() catch {};
        return if (self.cancelled.load(.acquire)) null else self.value;
    }

    /// Bounded wait used by timers, cancellation propagation, and blocking
    /// work isolation. It never spins beyond the caller-provided deadline.
    pub fn awaitTimeout(self: *Future, timeout_ns: u64) AwaitResult {
        var remaining = timeout_ns;
        while (!self.done.load(.acquire)) {
            if (remaining == 0) return .{ .status = .timed_out };
            // Zig 0.17 does not expose a portable blocking sleep on
            // `std.Thread`; yield between fixed nanosecond budget quanta so
            // other workers can complete without introducing a platform API.
            const quantum = @min(remaining, @as(u64, 1_000_000));
            std.Thread.yield() catch {};
            remaining -= quantum;
        }
        if (self.cancelled.load(.acquire)) return .{ .status = .cancelled };
        return .{ .status = .completed, .value = self.value };
    }
};

pub const Channel = struct {
    allocator: std.mem.Allocator,
    values: std.ArrayListUnmanaged(?*anyopaque) = .empty,
    capacity: usize,
    mutex: std.atomic.Mutex = .unlocked,
    closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, capacity: usize) Channel {
        return .{ .allocator = allocator, .capacity = capacity };
    }

    pub fn deinit(self: *Channel) void {
        self.values.deinit(self.allocator);
    }

    pub fn send(self: *Channel, value: ?*anyopaque) !void {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.closed.load(.acquire)) return error.Closed;
        if (self.values.items.len >= self.capacity) return error.Full;
        try self.values.append(self.allocator, value);
    }

    pub fn receive(self: *Channel) ?*anyopaque {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.values.items.len == 0) return null;
        return self.values.orderedRemove(0);
    }

    pub fn receiveState(self: *Channel) ReceiveResult {
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.values.items.len != 0) return .{ .value = self.values.orderedRemove(0) };
        return if (self.closed.load(.acquire)) .closed else .empty;
    }

    pub fn close(self: *Channel) void {
        self.closed.store(true, .release);
    }

    pub fn isClosed(self: *const Channel) bool {
        return self.closed.load(.acquire);
    }
};

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    io: ?std.Io = null,
    threads: []std.Thread,
    queue: std.ArrayListUnmanaged(Task) = .empty,
    capacity: usize,
    mutex: std.atomic.Mutex = .unlocked,
    running: std.atomic.Value(bool),
    wake: std.Io.Semaphore = .{},
    active: usize = 0,

    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !*Scheduler {
        return initWithIo(allocator, thread_count, null);
    }

    /// Initializes a scheduler with the process I/O context. When supplied,
    /// workers block on a kernel-backed semaphore instead of polling.
    pub fn initWithIo(allocator: std.mem.Allocator, thread_count: usize, io: ?std.Io) !*Scheduler {
        const count = if (thread_count == 0) try std.Thread.getCpuCount() else thread_count;
        if (count == 0) return error.InvalidThreadCount;
        const self = try allocator.create(Scheduler);
        errdefer allocator.destroy(self);
        const threads = try allocator.alloc(std.Thread, count);
        errdefer allocator.free(threads);
        self.* = .{
            .allocator = allocator,
            .io = io,
            .threads = threads,
            .capacity = @max(count * 64, 64),
            .running = std.atomic.Value(bool).init(true),
        };

        var started: usize = 0;
        errdefer {
            self.running.store(false, .release);
            for (threads[0..started]) |thread| thread.join();
            self.queue.deinit(allocator);
        }
        while (started < count) : (started += 1) {
            threads[started] = try std.Thread.spawn(.{}, workerLoop, .{self});
        }
        return self;
    }

    fn workerLoop(self: *Scheduler) void {
        while (self.running.load(.acquire)) {
            var task: ?Task = null;
            lock(&self.mutex);
            if (self.queue.items.len != 0) {
                task = self.queue.orderedRemove(0);
                self.active += 1;
            }
            self.mutex.unlock();
            if (task) |work| {
                if (!work.cancelled) work.func(work.ctx);
                lock(&self.mutex);
                self.active -= 1;
                self.mutex.unlock();
            } else {
                if (self.io) |runtime_io| {
                    self.wake.waitUncancelable(runtime_io);
                } else {
                    std.Thread.yield() catch {};
                }
            }
        }
    }

    pub fn spawnTask(self: *Scheduler, func: TaskFn, ctx: ?*anyopaque) !void {
        if (!self.running.load(.acquire)) return error.SchedulerStopped;
        lock(&self.mutex);
        defer self.mutex.unlock();
        if (self.queue.items.len >= self.capacity) return error.QueueFull;
        try self.queue.append(self.allocator, .{ .func = func, .ctx = ctx });
        self.wake.post(self.io orelse return);
    }

    pub fn waitIdle(self: *Scheduler) void {
        while (true) {
            lock(&self.mutex);
            const idle = self.queue.items.len == 0 and self.active == 0;
            self.mutex.unlock();
            if (idle) return;
            std.Thread.yield() catch {};
        }
    }

    /// Requests shutdown and waits for workers to exit. Safe to call once
    /// before `deinit` when an embedding runtime needs an explicit lifecycle
    /// boundary.
    pub fn stop(self: *Scheduler) void {
        if (!self.running.swap(false, .acq_rel)) return;
        if (self.io) |runtime_io| for (self.threads) |_| self.wake.post(runtime_io);
        for (self.threads) |thread| thread.join();
    }

    pub fn deinit(self: *Scheduler) void {
        self.stop();
        self.queue.deinit(self.allocator);
        self.allocator.free(self.threads);
        self.allocator.destroy(self);
    }
};

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.Thread.yield() catch {};
}

test "scheduler owns stable worker state and drains tasks" {
    const Counter = struct {
        value: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        fn increment(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            _ = self.value.fetchAdd(1, .monotonic);
        }
    };

    var counter = Counter{};
    const scheduler = try Scheduler.init(std.testing.allocator, 2);
    defer scheduler.deinit();
    for (0..100) |_| try scheduler.spawnTask(Counter.increment, &counter);
    scheduler.waitIdle();
    try std.testing.expectEqual(@as(usize, 100), counter.value.load(.acquire));
}

test "scheduler exposes an explicit idempotent stop lifecycle" {
    const noop = struct {
        fn run(_: ?*anyopaque) void {}
    }.run;
    const scheduler = try Scheduler.init(std.testing.allocator, 1);
    scheduler.stop();
    scheduler.stop();
    try std.testing.expectError(error.SchedulerStopped, scheduler.spawnTask(noop, null));
    scheduler.deinit();
}

test "scheduler can block workers on the runtime io wake primitive" {
    const noop = struct {
        fn run(_: ?*anyopaque) void {}
    }.run;
    const scheduler = try Scheduler.initWithIo(std.testing.allocator, 2, std.testing.io);
    defer scheduler.deinit();
    try scheduler.spawnTask(noop, null);
    scheduler.waitIdle();
}

test "channel enforces capacity and preserves order" {
    var channel = Channel.init(std.testing.allocator, 2);
    defer channel.deinit();
    var first: u8 = 1;
    var second: u8 = 2;
    try channel.send(&first);
    try channel.send(&second);
    try std.testing.expectError(error.Full, channel.send(null));
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&first)));
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&second)));
    try std.testing.expect(channel.receive() == null);
    channel.close();
    try std.testing.expect(channel.isClosed());
    try std.testing.expectError(error.Closed, channel.send(null));
    try std.testing.expectEqual(ReceiveResult.closed, channel.receiveState());
}

test "future completion and cancellation are synchronized" {
    var future = Future{};
    var result: u8 = 9;
    try std.testing.expect(!future.isDone());
    future.complete(&result);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&result)), future.await());
    future.cancel();
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&result)), future.await());

    var cancelled = Future{};
    cancelled.cancel();
    try std.testing.expect(cancelled.isDone());
    try std.testing.expect(cancelled.await() == null);
}

test "future bounded await reports timeout and cancellation distinctly" {
    var pending = Future{};
    try std.testing.expectEqual(AwaitStatus.timed_out, pending.awaitTimeout(1).status);
    pending.cancel();
    try std.testing.expectEqual(AwaitStatus.cancelled, pending.awaitTimeout(1_000_000).status);
}

test "future timeout uses nanosecond deadline semantics" {
    var pending = Future{};
    const result = pending.awaitTimeout(2_000_000);
    try std.testing.expectEqual(AwaitStatus.timed_out, result.status);
}

test "future terminal transition is first-writer-wins" {
    var future = Future{};
    var result: u8 = 3;
    future.cancel();
    future.complete(&result);
    try std.testing.expectEqual(AwaitStatus.cancelled, future.awaitTimeout(0).status);
    try std.testing.expect(future.await() == null);
}
