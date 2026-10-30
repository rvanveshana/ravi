const std = @import("std");
const builtin = @import("builtin");
const RuntimeError = @import("errors.zig").RuntimeError;

pub fn sleepMilliseconds(milliseconds: u64) RuntimeError!void {
    if (milliseconds == 0) return;
    if (comptime builtin.os.tag == .windows) {
        const ticks = std.math.mul(u64, milliseconds, 10_000) catch return error.IntegerOutOfRange;
        if (ticks > std.math.maxInt(std.os.windows.LARGE_INTEGER)) return error.IntegerOutOfRange;
        const interval: std.os.windows.LARGE_INTEGER = -@as(std.os.windows.LARGE_INTEGER, @intCast(ticks));
        _ = std.os.windows.ntdll.NtDelayExecution(.FALSE, &interval);
    } else if (comptime builtin.os.tag == .linux) {
        if (milliseconds / std.time.ms_per_s > std.math.maxInt(isize)) return error.IntegerOutOfRange;
        var remaining = std.os.linux.timespec{
            .sec = @intCast(milliseconds / std.time.ms_per_s),
            .nsec = @intCast((milliseconds % std.time.ms_per_s) * std.time.ns_per_ms),
        };
        while (true) switch (std.os.linux.errno(std.os.linux.nanosleep(&remaining, &remaining))) {
            .SUCCESS => return,
            .INTR => continue,
            else => return error.IoError,
        };
    } else {
        var backend = std.Io.Threaded.init(std.heap.smp_allocator, .{});
        defer backend.deinit();
        const nanoseconds = std.math.mul(u64, milliseconds, std.time.ns_per_ms) catch return error.IntegerOutOfRange;
        std.Io.sleep(backend.io(), .fromNanoseconds(nanoseconds), .awake) catch return error.IoError;
    }
}

test "Windows sleep rejects signed tick overflow before waiting" {
    if (builtin.os.tag != .windows) return;
    try std.testing.expectError(error.IntegerOutOfRange, sleepMilliseconds(922337203685478));
    try std.testing.expectError(error.IntegerOutOfRange, sleepMilliseconds(std.math.maxInt(u64)));
}
