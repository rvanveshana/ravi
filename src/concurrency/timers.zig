const std = @import("std");

pub fn push(self: anytype, timer: @TypeOf(self.timers[0])) void {
    var index = self.timer_count;
    self.timer_count += 1;
    while (index != 0) {
        const parent = (index - 1) / 2;
        if (self.timers[parent].deadline <= timer.deadline) break;
        self.timers[index] = self.timers[parent];
        index = parent;
    }
    self.timers[index] = timer;
}

pub fn pop(self: anytype) @TypeOf(self.timers[0]) {
    return remove(self, 0);
}

pub fn remove(self: anytype, first_index: usize) @TypeOf(self.timers[0]) {
    const first = self.timers[first_index];
    self.timer_count -= 1;
    if (self.timer_count == first_index) return first;
    const last = self.timers[self.timer_count];
    var index = first_index;
    if (index > 0 and last.deadline < self.timers[(index - 1) / 2].deadline) {
        while (index > 0) {
            const parent = (index - 1) / 2;
            if (self.timers[parent].deadline <= last.deadline) break;
            self.timers[index] = self.timers[parent];
            index = parent;
        }
        self.timers[index] = last;
        return first;
    }
    while (index * 2 + 1 < self.timer_count) {
        var child = index * 2 + 1;
        if (child + 1 < self.timer_count and self.timers[child + 1].deadline < self.timers[child].deadline) child += 1;
        if (last.deadline <= self.timers[child].deadline) break;
        self.timers[index] = self.timers[child];
        index = child;
    }
    self.timers[index] = last;
    return first;
}

pub fn run(self: anytype) void {
    const io = self.io();
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);
    while (true) {
        if (self.timer_count == 0) {
            if (!self.accepting and self.active == 0 and self.queued == 0) return;
            self.changed.waitUncancelable(io, &self.mutex);
            continue;
        }
        // Cancellation is an explicit notification, never an idle polling loop.
        var cancelled: ?usize = null;
        if (self.wake_scan) for (self.timers[0..self.timer_count], 0..) |timer, index| {
            if (timer.cancelled) |flag| if (flag.load(.acquire)) {
                cancelled = index;
                break;
            };
        };
        if (cancelled) |index| {
            const task = remove(self, index);
            if (self.queued == self.queue.len) {
                push(self, .{ .deadline = 0, .task = task.task, .cancelled = null });
            } else {
                self.queue[(self.head + self.queued) % self.queue.len] = task.task;
                self.queued += 1;
            }
            self.changed.broadcast(io);
            continue;
        }
        self.wake_scan = false;
        const deadline = self.timers[0].deadline;
        if (deadline == std.math.maxInt(i96)) {
            self.changed.waitUncancelable(io, &self.mutex);
            continue;
        }
        if (std.Io.Clock.now(.awake, io).nanoseconds < deadline) {
            self.changed.waitTimeout(io, &self.mutex, .{ .deadline = .{
                .clock = .awake,
                .raw = .{ .nanoseconds = deadline },
            } }) catch {};
            continue;
        }
        if (self.queued == self.queue.len) {
            self.changed.waitUncancelable(io, &self.mutex);
            continue;
        }
        const timer = pop(self);
        self.queue[(self.head + self.queued) % self.queue.len] = timer.task;
        self.queued += 1;
        self.changed.broadcast(io);
    }
}
