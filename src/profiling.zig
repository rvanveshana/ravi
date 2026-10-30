const std = @import("std");

/// Opt-in wall-clock phase measurements. The disabled path reads no clocks.
pub const Profile = struct {
    pub const Phase = enum { load, lex, parse, link, compile, execute };
    enabled: bool = false,
    io: std.Io,
    started: i96 = 0,
    elapsed: [6]i96 = @splat(0),

    pub fn begin(self: *Profile) void {
        if (self.enabled) self.started = std.Io.Clock.now(.awake, self.io).nanoseconds;
    }
    pub fn end(self: *Profile, phase: Phase) void {
        if (self.enabled) self.elapsed[@intFromEnum(phase)] += std.Io.Clock.now(.awake, self.io).nanoseconds - self.started;
    }
    pub fn report(self: *const Profile, vm: anytype, compiler: anytype) void {
        if (!self.enabled) return;
        inline for (@typeInfo(Phase).@"enum".field_names, 0..) |name, index|
            std.debug.print("profile {s}_ns={d}\n", .{ name, self.elapsed[index] });
        std.debug.print("profile analysis_ns={d} lowering_ns={d} optimization_ns={d} compiler_verification_ns={d}\n", .{ compiler.analysis, compiler.lowering, compiler.optimization, compiler.verification });
        const stats = vm.collector.statistics();
        std.debug.print("profile root_vm instructions={d} verification_ns={d} gc_ns={d} allocations={d} live={d} collections={d} bytes={d}\n", .{ vm.metrics.instructions, vm.metrics.verification_ns, vm.collector.collection_ns, stats.allocations, stats.live, stats.collections, stats.bytes });
        if (vm.task_scheduler) |pool| {
            const scheduler = pool.statistics();
            std.debug.print("profile scheduler workers={d} queued={d} running={d} timers={d} live_tasks={d}\n", .{ scheduler.workers, scheduler.queued, scheduler.running, scheduler.timers, scheduler.live_tasks });
        }
    }
};
