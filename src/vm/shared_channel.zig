const std = @import("std");
const Channel = @import("ravi_scheduler").Channel;
const Context = @import("task_context.zig").Context;
const Packet = @import("transfer.zig").Packet;
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;

/// Channel identity is shared explicitly. Messages are owned copy packets.
pub const Shared = struct {
    refs: std.atomic.Value(usize) = .init(1),
    channel: Channel,
    mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    waiters: ?*Context = null,

    pub fn create(capacity: usize) Error!*Shared {
        if (capacity == 0 or capacity > 4096) return error.TaskLimit;
        const self = std.heap.smp_allocator.create(Shared) catch return error.OutOfMemory;
        self.* = .{ .channel = Channel.init(std.heap.smp_allocator, capacity) };
        return self;
    }
    pub fn retain(self: *Shared) void {
        _ = self.refs.fetchAdd(1, .acq_rel);
    }
    pub fn release(self: *Shared) void {
        if (self.refs.fetchSub(1, .acq_rel) != 1) return;
        while (true) switch (self.channel.receiveState()) {
            .value => |raw| {
                const packet: *Packet = @ptrCast(@alignCast(raw.?));
                packet.destroy();
            },
            else => break,
        };
        self.channel.deinit();
        std.heap.smp_allocator.destroy(self);
    }
    pub fn lock(self: *Shared) void {
        self.mutex.lockUncancelable(self.channel.io());
    }
    pub fn unlock(self: *Shared) void {
        self.mutex.unlock(self.channel.io());
    }
    pub fn notify(self: *Shared) void {
        var waiter = self.waiters;
        while (waiter) |context| {
            context.wake.store(true, .release);
            context.pool.notify();
            waiter = context.next;
        }
        self.changed.broadcast(self.channel.io());
    }
    pub fn available(self: *Shared, sending: bool) bool {
        return self.channel.isClosed() or if (sending) self.channel.count < self.channel.capacity else self.channel.count != 0;
    }
};

pub fn resolve(vm: anytype, value: Value) Error!*Shared {
    if (value.handleKind() != .channel) return error.TypeGuardFailed;
    const slot = value.handleIndex().?;
    if (slot >= vm.channels.items.len) return error.InvalidInstruction;
    return vm.channels.items[slot];
}

pub fn attach(vm: anytype, shared: *Shared) Error!Value {
    if (vm.channels.items.len >= 4096) return error.TaskLimit;
    const slot = vm.channels.items.len;
    vm.channels.append(vm.allocator, shared) catch return error.OutOfMemory;
    shared.retain();
    return Value.fromHandle(.channel, slot) catch return error.TaskLimit;
}

pub fn operate(vm: anytype, id: @import("ravi_config").HostBuiltin, args: []const Value, ip: usize) Error!?Value {
    const shared = try resolve(vm, args[0]);
    shared.lock();
    defer shared.unlock();
    if (id == .channel_close) {
        shared.channel.close();
        shared.notify();
        return Value.nil();
    }
    const sending = id == .channel_send or id == .channel_send_timeout;
    const timed = id == .channel_send_timeout or id == .channel_recv_timeout;
    const until: ?i96 = if (timed) try @import("task_suspension.zig").deadline(vm, shared.channel.io(), ip, args[if (sending) 2 else 1]) else null;
    while (!shared.available(sending)) {
        if (until) |timestamp| if (std.Io.Clock.now(.awake, shared.channel.io()).nanoseconds >= timestamp) {
            vm.task_timeout_deadline = null;
            return error.TimedOut;
        };
        if (vm.cooperative) {
            vm.task_channel = shared;
            vm.task_channel_send = sending;
            vm.task_ip = ip;
            vm.task_deadline = until;
            return null;
        }
        if (until) |timestamp| {
            shared.changed.waitTimeout(shared.channel.io(), &shared.mutex, .{ .deadline = .{ .clock = .awake, .raw = .{ .nanoseconds = timestamp } } }) catch |err| {
                vm.task_timeout_deadline = null;
                return if (err == error.Timeout) error.TimedOut else error.Cancelled;
            };
        } else shared.changed.waitUncancelable(shared.channel.io(), &shared.mutex);
    }
    vm.task_timeout_deadline = null;
    if (sending) {
        if (shared.channel.isClosed()) return error.ChannelClosed;
        const packet = try Packet.createMessage(vm, args[1..2]);
        shared.channel.send(packet) catch |err| {
            packet.destroy();
            return if (err == error.OutOfMemory) error.OutOfMemory else error.ChannelClosed;
        };
        shared.notify();
        return Value.nil();
    }
    if (shared.channel.count == 0) return error.ChannelClosed;
    // Retain the queued message if decoding into the receiving heap fails.
    const raw = shared.channel.values.items[shared.channel.head].?;
    const packet: *Packet = @ptrCast(@alignCast(raw));
    const values = try packet.restore(vm);
    defer vm.allocator.free(values);
    _ = shared.channel.receiveState();
    packet.destroy();
    shared.notify();
    return values[0];
}
