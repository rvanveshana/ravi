const std = @import("std");
const Value = @import("ravi_vm_value").Value;

pub const Status = enum { pending, running, suspended, completed, failed, cancelled };
pub const Suspension = struct { instruction: usize, source_line: usize };
pub const Transition = struct { from: Status, to: Status, instruction: usize, source_line: usize };

pub const Cancellation = struct {
    parent: ?*Cancellation = null,
    cancelled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn cancel(self: *Cancellation) void {
        self.cancelled.store(true, .release);
    }

    pub fn isCancelled(self: *const Cancellation) bool {
        if (self.cancelled.load(.acquire)) return true;
        return if (self.parent) |parent| parent.isCancelled() else false;
    }
};

/// Explicit resumable state machine metadata shared by async functions,
/// generators, scheduler diagnostics, and DAP logical-frame views.
pub const Machine = struct {
    allocator: std.mem.Allocator,
    status: Status = .pending,
    instruction: usize = 0,
    source_line: usize = 0,
    result: Value = Value.nil(),
    has_result: bool = false,
    failure_code: ?i64 = null,
    cancellation: Cancellation = .{},
    transitions: std.ArrayListUnmanaged(Transition) = .empty,

    pub fn init(allocator: std.mem.Allocator) Machine {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Machine) void {
        self.transitions.deinit(self.allocator);
    }

    pub fn start(self: *Machine) !void {
        if (self.status != .pending) return error.InvalidTransition;
        try self.transition(.running, 0, 0);
    }

    pub fn suspendAt(self: *Machine, instruction: usize, source_line: usize) !void {
        if (self.status != .running or self.cancellation.isCancelled()) return error.InvalidTransition;
        self.instruction = instruction;
        self.source_line = source_line;
        try self.transition(.suspended, instruction, source_line);
    }

    pub fn resumeExecution(self: *Machine) !void {
        if (self.status != .suspended or self.cancellation.isCancelled()) return error.InvalidTransition;
        try self.transition(.running, self.instruction, self.source_line);
    }

    /// Returns the instruction/source location at which a suspended machine
    /// will continue.  Callers must still invoke resumeExecution to perform
    /// the state transition; this query is side-effect free for debuggers and
    /// schedulers.
    pub fn resumeLocation(self: *const Machine) ?Suspension {
        if (self.status != .suspended) return null;
        return .{ .instruction = self.instruction, .source_line = self.source_line };
    }

    pub fn isTerminal(self: *const Machine) bool {
        return switch (self.status) {
            .completed, .failed, .cancelled => true,
            else => false,
        };
    }

    pub fn complete(self: *Machine, value: Value) !void {
        if (self.status != .running and self.status != .suspended) return error.InvalidTransition;
        self.result = value;
        self.has_result = true;
        try self.transition(.completed, self.instruction, self.source_line);
    }

    pub fn fail(self: *Machine, code: i64) !void {
        if (self.status != .running and self.status != .suspended) return error.InvalidTransition;
        self.failure_code = code;
        try self.transition(.failed, self.instruction, self.source_line);
    }

    pub fn cancel(self: *Machine) !void {
        if (self.status == .completed or self.status == .failed or self.status == .cancelled) return error.InvalidTransition;
        self.cancellation.cancel();
        try self.transition(.cancelled, self.instruction, self.source_line);
    }

    /// Converts cancellation observed through a parent tree into a terminal
    /// machine state. Scheduler/VM safepoints can call this without needing
    /// to know whether cancellation originated locally or upstream.
    pub fn pollCancellation(self: *Machine) !bool {
        if (!self.cancellation.isCancelled()) return false;
        if (self.status == .completed or self.status == .failed or self.status == .cancelled) return true;
        try self.transition(.cancelled, self.instruction, self.source_line);
        return true;
    }

    fn transition(self: *Machine, next: Status, instruction: usize, source_line: usize) !void {
        try self.transitions.append(self.allocator, .{ .from = self.status, .to = next, .instruction = instruction, .source_line = source_line });
        self.status = next;
    }
};

test "async machine records suspension and resume source identity" {
    var machine = Machine.init(std.testing.allocator);
    defer machine.deinit();
    try machine.start();
    try machine.suspendAt(17, 4);
    try std.testing.expectEqual(Status.suspended, machine.status);
    try machine.resumeExecution();
    try machine.complete(Value.fromInt(42));
    try std.testing.expectEqual(Status.completed, machine.status);
    try std.testing.expectEqual(@as(usize, 4), machine.transitions.items[1].source_line);
    try std.testing.expectEqual(@as(i64, 42), machine.result.asInt());
}

test "cancellation propagates through child state machines" {
    var parent = Cancellation{};
    var child = Cancellation{ .parent = &parent };
    try std.testing.expect(!child.isCancelled());
    parent.cancel();
    try std.testing.expect(child.isCancelled());
    var machine = Machine.init(std.testing.allocator);
    defer machine.deinit();
    machine.cancellation.parent = &parent;
    try machine.start();
    try std.testing.expectError(error.InvalidTransition, machine.suspendAt(2, 1));
}

test "resumable machine exposes stable resume location and terminal state" {
    var machine = Machine.init(std.testing.allocator);
    defer machine.deinit();
    try machine.start();
    try machine.suspendAt(23, 11);
    const location = machine.resumeLocation() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 23), location.instruction);
    try std.testing.expectEqual(@as(usize, 11), location.source_line);
    try std.testing.expect(!machine.isTerminal());
    try machine.resumeExecution();
    try machine.complete(Value.nil());
    try std.testing.expect(machine.isTerminal());
    try std.testing.expect(machine.resumeLocation() == null);
}

test "parent cancellation is materialized at the child safepoint" {
    var parent = Cancellation{};
    var machine = Machine.init(std.testing.allocator);
    defer machine.deinit();
    machine.cancellation.parent = &parent;
    try machine.start();
    parent.cancel();
    try std.testing.expect(try machine.pollCancellation());
    try std.testing.expectEqual(Status.cancelled, machine.status);
    try std.testing.expectEqual(Status.running, machine.transitions.items[0].to);
    try std.testing.expectEqual(Status.cancelled, machine.transitions.items[1].to);
}
