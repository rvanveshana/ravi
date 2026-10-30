const std = @import("std");
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const Packet = @import("transfer.zig").Packet;
const Future = @import("tasks.zig").Future;
const Scheduler = @import("ravi_scheduler").Scheduler;
const Builtin = @import("ravi_config").HostBuiltin;

pub fn runtime(vm: anytype) Error!std.Io {
    if (vm.host_io) |io| return io;
    if (vm.host_backend == null) {
        const backend = vm.allocator.create(std.Io.Threaded) catch return error.OutOfMemory;
        backend.* = std.Io.Threaded.init(std.heap.smp_allocator, .{});
        vm.host_backend = backend;
    }
    return vm.host_backend.?.io();
}

const Job = struct {
    input: *Packet,
    future: *Future,
    pool: *Scheduler,
    id: Builtin,
    environ: std.process.Environ,
    fn run(raw: ?*anyopaque) void {
        const self: *Job = @ptrCast(@alignCast(raw.?));
        defer std.heap.smp_allocator.destroy(self);
        defer self.input.destroy();
        var vm = @import("vm.zig").Vm.init(std.heap.smp_allocator) catch {
            self.future.complete(self.pool, null, error.OutOfMemory);
            return;
        };
        defer vm.deinit();
        vm.host_io = self.pool.io();
        vm.environ = self.environ;
        const values = self.input.restore(&vm) catch |err| {
            self.future.complete(self.pool, null, err);
            return;
        };
        defer vm.allocator.free(values);
        const result = @import("host_calls.zig").perform(&vm, self.id, values);
        if (result) |value| {
            const packet = Packet.create(&vm, &.{value}) catch |err| {
                self.future.complete(self.pool, null, err);
                return;
            };
            self.future.complete(self.pool, packet, null);
        } else |err| self.future.complete(self.pool, null, err);
    }
};

pub fn start(vm: anytype, id: Builtin, values: []const Value, ip: usize) Error!void {
    const pool = vm.task_scheduler orelse return error.InvalidInstruction;
    const packet = try Packet.create(vm, values);
    errdefer packet.destroy();
    const future = std.heap.smp_allocator.create(Future) catch return error.OutOfMemory;
    errdefer std.heap.smp_allocator.destroy(future);
    future.* = .{};
    const job = std.heap.smp_allocator.create(Job) catch return error.OutOfMemory;
    errdefer std.heap.smp_allocator.destroy(job);
    job.* = .{ .input = packet, .future = future, .pool = pool, .id = id, .environ = vm.environ };
    const blocking = pool.blocking() catch return error.OutOfMemory;
    blocking.spawnTask(Job.run, job) catch return error.TaskQueueFull;
    vm.pending_io = future;
    vm.pending_io_ip = ip;
}
