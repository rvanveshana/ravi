const std = @import("std");
const bytecode = @import("ravi_bytecode");
const debug = @import("ravi_debug");
const gc = @import("ravi_gc");
const collections = @import("ravi_vm_collections");
const trace_runtime = @import("trace.zig");
const errors = @import("errors.zig");
const frames = @import("frames.zig");
const state_helpers = @import("state_helpers.zig");
const call_runtime = @import("call_runtime.zig");
const heap = @import("heap.zig");
const Value = @import("ravi_vm_value").Value;
const value_runtime = @import("value_runtime.zig");
const execution = @import("execution.zig");
const async_state = @import("ravi_async_state");
const scheduler = @import("ravi_scheduler");
pub const RuntimeValue = Value;
pub const collection_primitives = collections;

pub const RuntimeError = errors.RuntimeError;
pub const RuntimeType = errors.TypeId;
pub const ResumableResult = execution.ResumableResult;
const Frame = frames.Frame;

const tasks = @import("tasks.zig");
const TaskFuture = tasks.Future;

pub const TraceFrame = trace_runtime.Frame;
test {
    _ = @import("task_tests.zig");
    _ = @import("allocation_tests.zig");
}
pub const Vm = struct {
    allocator: std.mem.Allocator,
    stack: []Value,
    stack_top: usize = 0,
    frames: []Frame,
    frame_top: usize = 0,
    pub_printed: bool = false,
    arrays: []*heap.ManagedArray = &.{},
    array_count: usize = 0,
    dicts: []*heap.ManagedDict = &.{},
    dict_count: usize = 0,
    strings: std.ArrayListUnmanaged(*heap.ManagedString) = .empty,
    gc_roots: std.ArrayListUnmanaged(*anyopaque) = .empty,
    closures: []*heap.ManagedClosure = &.{},
    closure_count: usize = 0,
    cells: []*heap.ManagedCell = &.{},
    cell_count: usize = 0,
    instances: []*heap.ManagedInstance = &.{},
    instance_count: usize = 0,
    exceptions: []*heap.ManagedException = &.{},
    exception_count: usize = 0,
    last_exception: Value = Value.nil(),
    trace: []TraceFrame,
    trace_count: usize = 0,
    handler_active: bool = false,
    handler_ip: usize = 0,
    handler_stack_top: usize = 0,
    handler_frame_top: usize = 0,
    handler_trace_count: usize = 0,
    fault_ip: usize = 0,
    debugger: ?*debug.Debugger = null,
    collector: gc.Collector,
    resumable_machine: ?async_state.Machine = null,
    resumable_chunk: ?*const bytecode.Chunk = null,
    resumable_ip: usize = 0,
    resumable_started: bool = false,
    task_scheduler: ?*scheduler.Scheduler = null,
    worker_count: usize = 0,
    futures: std.ArrayListUnmanaged(*TaskFuture) = .empty,
    pub fn init(allocator: std.mem.Allocator) !Vm {
        return initWithCollectorOptions(allocator, .{});
    }
    pub fn initWithCollectorOptions(allocator: std.mem.Allocator, options: gc.Collector.Options) !Vm {
        const stack = try allocator.alloc(Value, 256);
        errdefer allocator.free(stack);
        const call_frames = try allocator.alloc(Frame, 64);
        errdefer allocator.free(call_frames);
        for (call_frames) |*frame| frame.* = .{};
        const trace_frames = try allocator.alloc(TraceFrame, 64);
        return .{ .allocator = allocator, .stack = stack, .frames = call_frames, .trace = trace_frames, .collector = gc.Collector.initWithOptions(allocator, options) };
    }
    pub fn deinit(self: *Vm) void {
        if (self.resumable_machine) |*machine| machine.deinit();
        if (self.task_scheduler) |value| value.deinit();
        for (self.futures.items) |future| self.allocator.destroy(future);
        self.futures.deinit(self.allocator);
        state_helpers.deinit(self);
        self.collector.deinit();
    }
    pub fn run(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!i64 {
        return value_runtime.toLegacy(try self.execute(chunk));
    }
    pub fn runValue(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!Value {
        chunk.verify() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidInstruction;
        return self.execute(chunk);
    }
    pub fn runResumable(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!ResumableResult {
        if (self.resumable_machine != null) return error.InvalidInstruction;
        var machine = async_state.Machine.init(self.allocator);
        machine.start() catch return error.OutOfMemory;
        self.resumable_machine = machine;
        self.resumable_chunk = chunk;
        self.resumable_ip = 0;
        self.resumable_started = false;
        return self.resumeResumable();
    }
    pub fn resumeResumable(self: *Vm) RuntimeError!ResumableResult {
        const chunk = self.resumable_chunk orelse return error.InvalidInstruction;
        const machine = &(self.resumable_machine orelse return error.InvalidInstruction);
        if (machine.status == .suspended) machine.resumeExecution() catch return error.InvalidInstruction;
        if (machine.status == .completed) return .{ .completed = machine.result };
        if (machine.status != .running) return error.InvalidInstruction;
        const result = try execution.executeResumable(self, chunk, machine, &self.resumable_ip, !self.resumable_started);
        self.resumable_started = true;
        return result;
    }
    pub fn resumableStatus(self: *const Vm) ?async_state.Status {
        return if (self.resumable_machine) |machine| machine.status else null;
    }

    /// Execute a compact release artifact using the normal VM semantics.
    /// Metadata is copied from the compiled template so calls, classes, and
    /// source-independent operands retain their original meaning. Debugger
    /// attachment is deliberately rejected: packed artifacts have no packed
    /// source-location stream and must use `runValue` with the source chunk.
    pub fn runPackedValue(self: *Vm, template: *const bytecode.Chunk, bytes: []const u8) RuntimeError!Value {
        if (self.debugger != null) return error.InvalidInstruction;
        var chunk = bytecode.Chunk.init(self.allocator);
        defer chunk.deinit();
        const decoded = bytecode.decodePackedCode(self.allocator, bytes) catch return error.InvalidInstruction;
        defer self.allocator.free(decoded);
        chunk.code.appendSlice(self.allocator, decoded) catch return error.OutOfMemory;
        // A release chunk still needs a structurally valid source map for the
        // verifier; locations are intentionally zeroed rather than guessed.
        for (chunk.code.items) |_| chunk.source_map.append(self.allocator, .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 }) catch return error.OutOfMemory;
        for (chunk.code.items) |_| chunk.root_map.append(self.allocator, .{}) catch return error.OutOfMemory;
        for (template.strings.items) |text| _ = chunk.addString(text) catch return error.OutOfMemory;
        chunk.formats.appendSlice(self.allocator, template.formats.items) catch return error.OutOfMemory;
        chunk.floats.appendSlice(self.allocator, template.floats.items) catch return error.OutOfMemory;
        chunk.functions.appendSlice(self.allocator, template.functions.items) catch return error.OutOfMemory;
        chunk.classes.appendSlice(self.allocator, template.classes.items) catch return error.OutOfMemory;
        chunk.methods.appendSlice(self.allocator, template.methods.items) catch return error.OutOfMemory;
        chunk.captures.appendSlice(self.allocator, template.captures.items) catch return error.OutOfMemory;
        return self.runValue(&chunk);
    }
    pub fn attachDebugger(self: *Vm, debugger: *debug.Debugger) void {
        self.debugger = debugger;
    }
    pub fn detachDebugger(self: *Vm) void {
        self.debugger = null;
    }
    pub fn collectGarbage(self: *Vm) RuntimeError!void {
        return self.collector.collect() catch error.OutOfMemory;
    }
    pub fn collectorStatistics(self: *const Vm) gc.Collector.Statistics {
        return self.collector.statistics();
    }
    pub fn spawnTask(self: *Vm, chunk: *const bytecode.Chunk, function_index: usize, args: []const Value) RuntimeError!Value {
        return tasks.spawn(self, chunk, function_index, args);
    }
    pub fn waitTask(self: *Vm, handle: Value) RuntimeError!Value {
        return tasks.wait(self, handle);
    }
    fn execute(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!Value {
        return execution.execute(self, chunk);
    }
    fn push(self: *Vm, value: Value) RuntimeError!void {
        return state_helpers.push(self, value);
    }
    fn handleFault(self: *Vm, ip: *usize) bool {
        return state_helpers.handleFault(self, ip);
    }
    fn callMethod(self: *Vm, chunk: *const bytecode.Chunk, operand: i64, ip: *usize) RuntimeError!void {
        try state_helpers.ensureCallCapacity(self);
        return call_runtime.callMethod(self, chunk, operand, ip);
    }
    fn callSuper(self: *Vm, chunk: *const bytecode.Chunk, operand: i64, ip: *usize) RuntimeError!void {
        try state_helpers.ensureCallCapacity(self);
        return call_runtime.callSuper(self, chunk, operand, ip);
    }
    pub fn stringSlice(self: *const Vm, handle: Value) ?[]const u8 {
        if (handle.handleKind() != .string) return null;
        const slot = handle.handleIndex().?;
        if (slot >= self.strings.items.len) return null;
        return self.strings.items[slot].bytes;
    }
    fn internString(self: *Vm, text: []const u8) RuntimeError!Value {
        return state_helpers.internString(self, text);
    }
    fn call(self: *Vm, chunk: *const bytecode.Chunk, operand: i64, ip: *usize) RuntimeError!void {
        try state_helpers.ensureCallCapacity(self);
        return call_runtime.call(self, chunk, operand, ip);
    }
    fn callValue(self: *Vm, chunk: *const bytecode.Chunk, arity_operand: i64, ip: *usize) RuntimeError!void {
        try state_helpers.ensureCallCapacity(self);
        return call_runtime.callValue(self, chunk, arity_operand, ip);
    }
};

test "VM debugger attachment pauses at instruction breakpoints" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .halt });
    var debugger = debug.Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    _ = try debugger.addBreakpoint(0);
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    vm.attachDebugger(&debugger);
    try std.testing.expectError(error.DebuggerPaused, vm.runValue(&chunk));
    vm.detachDebugger();
    _ = try vm.runValue(&chunk);
}

test "VM resumable execution yields and resumes at the next instruction" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 7 });
    try chunk.emit(.{ .op = .suspend_point, .operand = 12 });
    try chunk.emit(.{ .op = .return_value });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    switch (try vm.runResumable(&chunk)) {
        .suspended => |value| try std.testing.expectEqual(@as(i64, 7), value.asInt()),
        .completed => return error.TestExpectedEqual,
    }
    try std.testing.expectEqual(async_state.Status.suspended, vm.resumableStatus().?);
    switch (try vm.resumeResumable()) {
        .suspended => return error.TestExpectedEqual,
        .completed => |value| try std.testing.expectEqual(@as(i64, 7), value.asInt()),
    }
    try std.testing.expectEqual(async_state.Status.completed, vm.resumableStatus().?);
}

test "VM interning scales beyond the legacy thousand-string cap" {
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    var buffer: [32]u8 = undefined;
    for (0..1_024) |index| {
        const text = try std.fmt.bufPrint(&buffer, "string-{d}", .{index});
        _ = try vm.internString(text);
    }
    try std.testing.expect(vm.strings.items.len >= 1_024);
}

test "VM preserves the active exception when a handler rethrows" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    try chunk.emit(.{ .op = .try_begin, .operand = 4 });
    try chunk.emit(.{ .op = .raise_value });
    try chunk.emit(.{ .op = .halt });
    try chunk.emit(.{ .op = .raise_value });
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.RaisedException, vm.runValue(&chunk));
    try std.testing.expect(vm.last_exception.isInt());
    try std.testing.expectEqual(@as(i64, 42), vm.last_exception.asInt());
}
