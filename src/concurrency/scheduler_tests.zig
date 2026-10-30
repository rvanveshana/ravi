const std = @import("std");
const scheduler_module = @import("scheduler.zig");
const Scheduler = scheduler_module.Scheduler;
const Future = scheduler_module.Future;
const Channel = scheduler_module.Channel;
const AwaitStatus = scheduler_module.AwaitStatus;
const ReceiveResult = scheduler_module.ReceiveResult;

test "scheduler owns stable worker state and drains tasks" {
    const Counter = struct {
        value: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        fn increment(context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            _ = self.value.fetchAdd(1, .monotonic);
        }
    };

    var counter = Counter{};
    const scheduler = try Scheduler.init(std.testing.allocator, 2);
    defer scheduler.deinit();
    for (0..100) |_| try scheduler.spawnTask(Counter.increment, &counter);
    scheduler.waitIdle();
    try std.testing.expectEqual(@as(usize, 100), counter.value.load(.acquire));
}

test "scheduler exposes an explicit idempotent stop lifecycle" {
    const noop = struct {
        fn run(_: ?*anyopaque) void {}
    }.run;
    const scheduler = try Scheduler.init(std.testing.allocator, 1);
    scheduler.stop();
    scheduler.stop();
    try std.testing.expectError(error.SchedulerStopped, scheduler.spawnTask(noop, null));
    scheduler.deinit();
}

test "scheduler can block workers on the runtime io wake primitive" {
    const noop = struct {
        fn run(_: ?*anyopaque) void {}
    }.run;
    const scheduler = try Scheduler.init(std.testing.allocator, 2);
    defer scheduler.deinit();
    try scheduler.spawnTask(noop, null);
    scheduler.waitIdle();
}

test "channel enforces capacity and preserves order" {
    var channel = Channel.init(std.testing.allocator, 2);
    defer channel.deinit();
    var first: u8 = 1;
    var second: u8 = 2;
    try channel.send(&first);
    try channel.send(&second);
    try std.testing.expectError(error.Full, channel.send(null));
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&first)));
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&second)));
    try std.testing.expect(channel.receive() == null);
    channel.close();
    try std.testing.expect(channel.isClosed());
    try std.testing.expectError(error.Closed, channel.send(null));
    try std.testing.expectEqual(ReceiveResult.closed, channel.receiveState());
}

test "future completion and cancellation are synchronized" {
    var future = Future{};
    var result: u8 = 9;
    try std.testing.expect(!future.isDone());
    future.complete(std.testing.io, &result);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&result)), future.await(std.testing.io));
    future.cancel(std.testing.io);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&result)), future.await(std.testing.io));

    var cancelled = Future{};
    cancelled.cancel(std.testing.io);
    try std.testing.expect(cancelled.isDone());
    try std.testing.expect(cancelled.await(std.testing.io) == null);
}

test "future bounded await reports timeout and cancellation distinctly" {
    var pending = Future{};
    try std.testing.expectEqual(AwaitStatus.timed_out, (try pending.awaitTimeout(std.testing.io, 1)).status);
    pending.cancel(std.testing.io);
    try std.testing.expectEqual(AwaitStatus.cancelled, (try pending.awaitTimeout(std.testing.io, 1_000_000)).status);
}

test "future timeout uses nanosecond deadline semantics" {
    var pending = Future{};
    const start = std.Io.Clock.now(.awake, std.testing.io);
    const result = try pending.awaitTimeout(std.testing.io, 2_000_000);
    try std.testing.expectEqual(AwaitStatus.timed_out, result.status);
    const elapsed = start.durationTo(std.Io.Clock.now(.awake, std.testing.io));
    try std.testing.expect(elapsed.nanoseconds >= 2_000_000);
}

test "stop drains accepted work without an explicit idle wait" {
    const Work = struct {
        count: std.atomic.Value(usize) = .init(0),
        fn run(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            _ = self.count.fetchAdd(1, .monotonic);
        }
    };
    var work = Work{};
    const pool = try Scheduler.init(std.testing.allocator, 1);
    defer pool.deinit();
    for (0..64) |_| try pool.spawnTask(Work.run, &work);
    pool.stop();
    try std.testing.expectEqual(@as(usize, 64), work.count.load(.acquire));
    try std.testing.expectError(error.SchedulerStopped, pool.spawnTask(Work.run, &work));
}

test "future completion wakes a timed waiter with its payload" {
    const Work = struct {
        future: Future = .{},
        value: u8 = 42,
        io: std.Io,
        fn run(ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.future.complete(self.io, &self.value);
        }
    };
    const pool = try Scheduler.init(std.testing.allocator, 1);
    defer pool.deinit();
    var work = Work{ .io = pool.io() };
    try pool.spawnTask(Work.run, &work);
    defer pool.waitIdle();
    const result = try work.future.awaitTimeout(pool.io(), 5 * std.time.ns_per_s);
    try std.testing.expectEqual(AwaitStatus.completed, result.status);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&work.value)), result.value);
}

test "future terminal transition is first-writer-wins" {
    var future = Future{};
    var result: u8 = 3;
    future.cancel(std.testing.io);
    future.complete(std.testing.io, &result);
    try std.testing.expectEqual(AwaitStatus.cancelled, (try future.awaitTimeout(std.testing.io, 0)).status);
    try std.testing.expect(future.await(std.testing.io) == null);
}

test "channel ring wraps and drains after close including null payloads" {
    var channel = Channel.init(std.testing.allocator, 3);
    defer channel.deinit();
    var payloads = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expectEqual(ReceiveResult.empty, channel.receiveState());
    try channel.send(&payloads[0]);
    try channel.send(&payloads[1]);
    try channel.send(null);
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&payloads[0])));
    try channel.send(&payloads[2]);
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&payloads[1])));
    try channel.send(&payloads[3]);
    channel.close();
    try std.testing.expectError(error.Closed, channel.send(null));
    const result = channel.receiveState();
    try std.testing.expect(result == .value);
    try std.testing.expect(result.value == null);
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&payloads[2])));
    try std.testing.expect(channel.receive() == @as(*anyopaque, @ptrCast(&payloads[3])));
    try std.testing.expectEqual(ReceiveResult.closed, channel.receiveState());
}

test "zero capacity channel rejects sends without allocating" {
    var channel = Channel.init(std.testing.failing_allocator, 0);
    defer channel.deinit();
    try std.testing.expectError(error.Full, channel.send(null));
    try std.testing.expectEqual(ReceiveResult.empty, channel.receiveState());
    channel.close();
    try std.testing.expectEqual(ReceiveResult.closed, channel.receiveState());
}

test "channel allocation failure does not publish a value" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var channel = Channel.init(failing.allocator(), 2);
    defer channel.deinit();
    try std.testing.expectError(error.OutOfMemory, channel.send(null));
    try std.testing.expectEqual(ReceiveResult.empty, channel.receiveState());
    failing.fail_index = std.math.maxInt(usize);
    try channel.send(null);
    try std.testing.expect(channel.receiveState() == .value);
    try std.testing.expectEqual(ReceiveResult.empty, channel.receiveState());
}
