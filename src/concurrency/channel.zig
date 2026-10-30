const std = @import("std");
pub const ReceiveResult = union(enum) { value: ?*anyopaque, empty, closed, timed_out };

pub const Channel = struct {
    allocator: std.mem.Allocator,
    values: std.ArrayListUnmanaged(?*anyopaque) = .empty,
    capacity: usize,
    head: usize = 0,
    count: usize = 0,
    backend: std.Io.Threaded,
    mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    closed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: std.mem.Allocator, capacity: usize) Channel {
        return .{ .allocator = allocator, .capacity = capacity, .backend = std.Io.Threaded.init(std.heap.smp_allocator, .{}) };
    }

    pub fn deinit(self: *Channel) void {
        self.values.deinit(self.allocator);
        self.backend.deinit();
    }

    pub fn io(self: *Channel) std.Io {
        return self.backend.io();
    }

    /// Every observer uses this channel's runtime; owners join observers before deinit.
    pub fn sendTimeout(self: *Channel, value: ?*anyopaque, timeout_ns: u64) !void {
        const runtime = self.io();
        const deadline = std.Io.Clock.Timestamp.fromNow(runtime, .{ .clock = .awake, .raw = .fromNanoseconds(timeout_ns) });
        self.mutex.lockUncancelable(runtime);
        defer self.mutex.unlock(runtime);
        if (self.capacity == 0) return error.Full;
        while (self.count == self.capacity and !self.closed.load(.acquire)) {
            self.changed.waitTimeout(runtime, &self.mutex, .{ .deadline = deadline }) catch |err| return err;
        }
        if (self.closed.load(.acquire)) return error.Closed;
        if (self.values.items.len == 0) {
            try self.values.resize(self.allocator, self.capacity);
            @memset(self.values.items, null);
        }
        self.values.items[(self.head + self.count) % self.capacity] = value;
        self.count += 1;
        self.changed.broadcast(runtime);
    }

    pub fn receiveTimeout(self: *Channel, timeout_ns: u64) !ReceiveResult {
        const runtime = self.io();
        const deadline = std.Io.Clock.Timestamp.fromNow(runtime, .{ .clock = .awake, .raw = .fromNanoseconds(timeout_ns) });
        self.mutex.lockUncancelable(runtime);
        defer self.mutex.unlock(runtime);
        while (self.count == 0 and !self.closed.load(.acquire)) {
            self.changed.waitTimeout(runtime, &self.mutex, .{ .deadline = deadline }) catch |err| switch (err) {
                error.Timeout => return .timed_out,
                error.Canceled => return error.Canceled,
            };
        }
        if (self.count != 0) return .{ .value = self.take() };
        return .closed;
    }

    pub fn send(self: *Channel, value: ?*anyopaque) !void {
        self.mutex.lockUncancelable(self.io());
        defer self.mutex.unlock(self.io());
        if (self.closed.load(.acquire)) return error.Closed;
        if (self.count >= self.capacity) return error.Full;
        // Allocate once before publishing the first value. Every subsequent
        // send/receive is O(1), including after the ring wraps.
        if (self.values.items.len == 0) {
            try self.values.resize(self.allocator, self.capacity);
            @memset(self.values.items, null);
        }
        self.values.items[(self.head + self.count) % self.capacity] = value;
        self.count += 1;
        self.changed.broadcast(self.io());
    }

    pub fn receive(self: *Channel) ?*anyopaque {
        self.mutex.lockUncancelable(self.io());
        defer self.mutex.unlock(self.io());
        if (self.count == 0) return null;
        return self.take();
    }

    pub fn receiveState(self: *Channel) ReceiveResult {
        self.mutex.lockUncancelable(self.io());
        defer self.mutex.unlock(self.io());
        if (self.count != 0) return .{ .value = self.take() };
        return if (self.closed.load(.acquire)) .closed else .empty;
    }

    pub fn close(self: *Channel) void {
        self.mutex.lockUncancelable(self.io());
        defer self.mutex.unlock(self.io());
        self.closed.store(true, .release);
        self.changed.broadcast(self.io());
    }

    pub fn isClosed(self: *const Channel) bool {
        return self.closed.load(.acquire);
    }

    // Caller holds the mutex and has checked that the ring is nonempty.
    fn take(self: *Channel) ?*anyopaque {
        const value = self.values.items[self.head];
        self.values.items[self.head] = null;
        self.head = (self.head + 1) % self.capacity;
        self.count -= 1;
        self.changed.broadcast(self.io());
        return value;
    }
};
