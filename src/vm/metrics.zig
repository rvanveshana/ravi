const std = @import("std");

pub const Metrics = struct {
    enabled: bool = false,
    instructions: u64 = 0,
    verification_ns: i96 = 0,

    pub fn now(self: *const Metrics, io: ?std.Io) i96 {
        if (self.enabled) if (io) |runtime| return std.Io.Clock.now(.awake, runtime).nanoseconds;
        return 0;
    }
    pub fn record(self: *Metrics) void {
        if (self.enabled) self.instructions +|= 1;
    }
};
