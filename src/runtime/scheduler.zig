const std = @import("std");

pub const TaskFn = *const fn (?*anyopaque) void;
pub const Task = struct { function: TaskFn, context: ?*anyopaque, cancelled: bool = false };
pub const Future = struct { done: bool = false, value: ?*anyopaque = null, cancelled: bool = false };
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
    capacity: usize,
    queue: std.ArrayListUnmanaged(Task) = .empty,
    pub fn init(allocator: std.mem.Allocator, capacity: usize) Scheduler {
        return .{ .allocator = allocator, .capacity = capacity };
    }
    pub fn deinit(self: *Scheduler) void {
        self.queue.deinit(self.allocator);
    }
    pub fn spawn(self: *Scheduler, function: TaskFn, context: ?*anyopaque) !void {
        if (self.queue.items.len >= self.capacity) return error.QueueFull;
        try self.queue.append(self.allocator, .{ .function = function, .context = context });
    }
    pub fn cancelAll(self: *Scheduler) void {
        for (self.queue.items) |*task| task.cancelled = true;
    }
    pub fn runOne(self: *Scheduler) bool {
        if (self.queue.items.len == 0) return false;
        const task = self.queue.orderedRemove(0);
        if (!task.cancelled) task.function(task.context);
        return true;
    }
};
