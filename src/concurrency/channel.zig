const std = @import("std");
pub const ReceiveResult = union(enum) { value: ?*anyopaque, empty, closed };

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
        lock(&self.mutex);
        defer self.mutex.unlock();
        self.closed.store(true, .release);
    }

    pub fn isClosed(self: *const Channel) bool {
        return self.closed.load(.acquire);
    }
};

fn lock(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) std.Thread.yield() catch {};
}
