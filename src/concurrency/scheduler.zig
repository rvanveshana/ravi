const std = @import("std");

pub const TaskFn = *const fn (ctx: ?*anyopaque) void;

pub const Task = struct {
    func: TaskFn,
    ctx: ?*anyopaque = null,
    cancelled: bool = false,
};

pub const Future = struct {
    done: bool = false,
    value: ?*anyopaque = null,
    cancelled: bool = false,
};

pub const Channel = struct {
    allocator: std.mem.Allocator,
    values: std.ArrayListUnmanaged(?*anyopaque) = .empty,
    capacity: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) Channel {
        return .{ .allocator = allocator, .capacity = capacity };
    }

    pub fn deinit(self: *Channel) void {
        self.values.deinit(self.allocator);
    }

    pub fn send(self: *Channel, value: ?*anyopaque) !void {
        if (self.values.items.len >= self.capacity) return error.Full;
        try self.values.append(self.allocator, value);
    }

    pub fn receive(self: *Channel) ?*anyopaque {
        if (self.values.items.len == 0) return null;
        return self.values.orderedRemove(0);
    }
};

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    threads: []std.Thread,
    queue: std.Thread.Queue(Task),
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !Scheduler {
        const count = if (thread_count == 0) try std.Thread.getCpuCount() else thread_count;
        var threads = try allocator.alloc(std.Thread, count);
        var self = Scheduler{
            .allocator = allocator,
            .threads = threads,
            .queue = .{},
            .running = std.atomic.Value(bool).init(true),
        };

        for (0..count) |i| {
            threads[i] = try std.Thread.spawn(.{}, workerLoop, .{&self});
        }
        return self;
    }

    fn workerLoop(self: *Scheduler) void {
        while (self.running.load(.unordered)) {
            if (self.queue.pop()) |task| {
                if (!task.cancelled) {
                    task.func(task.ctx);
                }
            } else {
                std.Thread.sleep(100_000); // 100 microseconds spin relaxation
            }
        }
    }

    pub fn spawnTask(self: *Scheduler, func: TaskFn, ctx: ?*anyopaque) !void {
        const node = try self.allocator.create(std.Thread.Queue(Task).Node);
        node.data = .{ .func = func, .ctx = ctx };
        self.queue.push(node);
    }

    pub fn deinit(self: *Scheduler) void {
        self.running.store(false, .release);
        for (self.threads) |thread| {
            thread.join();
        }
        self.allocator.free(self.threads);
    }
};
