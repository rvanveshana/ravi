const std = @import("std");

pub const AwaitStatus = enum { completed, cancelled, timed_out };
pub const AwaitResult = struct { status: AwaitStatus, value: ?*anyopaque = null };

/// A single-assignment completion. All observers must use the same I/O runtime.
pub const Future = struct {
    ready: std.Io.Event = .unset,
    mutex: std.Io.Mutex = .init,
    value: ?*anyopaque = null,
    cancelled: bool = false,

    pub fn complete(self: *Future, io: std.Io, value: ?*anyopaque) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.ready.isSet()) return;
        self.value = value;
        self.ready.set(io);
    }

    pub fn cancel(self: *Future, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.ready.isSet()) return;
        self.cancelled = true;
        self.ready.set(io);
    }

    pub fn isDone(self: *const Future) bool {
        return self.ready.isSet();
    }

    pub fn await(self: *Future, io: std.Io) ?*anyopaque {
        self.ready.waitUncancelable(io);
        return if (self.cancelled) null else self.value;
    }

    pub fn awaitTimeout(self: *Future, io: std.Io, timeout_ns: u64) std.Io.Cancelable!AwaitResult {
        const deadline = std.Io.Clock.Timestamp.fromNow(io, .{
            .clock = .awake,
            .raw = .fromNanoseconds(timeout_ns),
        });
        while (!self.ready.isSet()) {
            if (std.Io.Clock.now(.awake, io).nanoseconds >= deadline.raw.nanoseconds)
                return .{ .status = .timed_out };
            self.ready.waitTimeout(io, .{ .deadline = deadline }) catch |err| switch (err) {
                // A futex can wake spuriously. Recheck the original deadline.
                error.Timeout => continue,
                error.Canceled => return error.Canceled,
            };
        }
        return if (self.cancelled) .{ .status = .cancelled } else .{ .status = .completed, .value = self.value };
    }
};
