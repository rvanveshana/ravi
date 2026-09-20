const std = @import("std");
const builtin = @import("builtin");
const RuntimeError = @import("errors.zig").RuntimeError;

pub fn sleepMilliseconds(milliseconds: u64) RuntimeError!void {
    if (milliseconds == 0) return;
    if (comptime builtin.os.tag == .windows) {
        const ticks = std.math.mul(u64, milliseconds, 10_000) catch return error.IntegerOutOfRange;
        const interval: std.os.windows.LARGE_INTEGER = -@as(std.os.windows.LARGE_INTEGER, @intCast(ticks));
        _ = std.os.windows.ntdll.NtDelayExecution(.FALSE, &interval);
    } else {
        var remaining = std.posix.timespec{
            .sec = @intCast(milliseconds / std.time.ms_per_s),
            .nsec = @intCast((milliseconds % std.time.ms_per_s) * std.time.ns_per_ms),
        };
        while (std.posix.nanosleep(&remaining, &remaining) != 0) {}
    }
}
