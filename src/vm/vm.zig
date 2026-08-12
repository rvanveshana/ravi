const std = @import("std");
const bytecode = @import("ravi_bytecode");
const debug = @import("ravi_debug");
const gc = @import("ravi_gc");
const dispatch = @import("ravi_dispatch");
const collections = @import("ravi_vm_collections");
const string_runtime = @import("strings.zig");
const trace_runtime = @import("trace.zig");
const errors = @import("errors.zig");
const frames = @import("frames.zig");
const type_helpers = @import("type_helpers.zig");
const state_helpers = @import("state_helpers.zig");
const call_runtime = @import("call_runtime.zig");
const object_storage = @import("object_storage.zig");
const heap = @import("heap.zig");
const Value = @import("ravi_vm_value").Value;
const value_runtime = @import("value_runtime.zig");
const operators = @import("operators.zig");
const formatting = @import("formatting.zig");
const collection_views = @import("collection_views.zig");
const collection_access = @import("collection_access.zig");
const slicing = @import("slicing.zig");
const collection_mutation = @import("collection_mutation.zig");
const value_operations = @import("value_operations.zig");
const string_operations = @import("string_operations.zig");
const construction = @import("construction.zig");
const exceptions = @import("exceptions.zig");
const frame_access = @import("frame_access.zig");
const string_construction = @import("string_construction.zig");
const range_operations = @import("range_operations.zig");
const stack_operations = @import("stack_operations.zig");
const arithmetic_operations = @import("arithmetic_operations.zig");
const control_flow = @import("control_flow.zig");
const integer = value_runtime.integer;
const makeHandle = value_runtime.makeHandle;
const requireInteger = value_runtime.requireInteger;
const arraySlot = value_runtime.arraySlot;
const dictSlot = value_runtime.dictSlot;
const instanceSlot = value_runtime.instanceSlot;
pub const RuntimeValue = Value;
pub const collection_primitives = collections;

pub const RuntimeError = errors.RuntimeError;
pub const RuntimeType = errors.TypeId;
const Frame = frames.Frame;

pub const TraceFrame = trace_runtime.Frame;
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
    pub fn init(allocator: std.mem.Allocator) !Vm {
        const stack = try allocator.alloc(Value, 256);
        errdefer allocator.free(stack);
        const call_frames = try allocator.alloc(Frame, 64);
        errdefer allocator.free(call_frames);
        for (call_frames) |*frame| frame.* = .{};
        const trace_frames = try allocator.alloc(TraceFrame, 64);
        return .{ .allocator = allocator, .stack = stack, .frames = call_frames, .trace = trace_frames, .collector = gc.Collector.init(allocator) };
    }
    pub fn deinit(self: *Vm) void {
        state_helpers.deinit(self);
        self.collector.deinit();
    }
    pub fn run(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!i64 {
        return value_runtime.toLegacy(try self.execute(chunk));
    }
    pub fn runValue(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!Value {
        chunk.verify() catch return error.InvalidInstruction;
        if (self.debugger == null and dispatch.FastDispatcher.supports(chunk.code.items)) {
            var fast_stack: [256]Value = undefined;
            return switch (dispatch.FastDispatcher.dispatchLoop(chunk.code.items, &fast_stack)) {
                .ok => |value| value,
                .runtime_error => error.InvalidInstruction,
            };
        }
        return self.execute(chunk);
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
        if (template.functions.items.len == 0 and template.classes.items.len == 0 and
            self.debugger == null and dispatch.FastDispatcher.supports(decoded))
        {
            var fast_stack: [256]Value = undefined;
            return switch (dispatch.FastDispatcher.dispatchLoop(decoded, &fast_stack)) {
                .ok => |value| value,
                .runtime_error => error.InvalidInstruction,
            };
        }
        chunk.code.appendSlice(self.allocator, decoded) catch return error.OutOfMemory;
        // A release chunk still needs a structurally valid source map for the
        // verifier; locations are intentionally zeroed rather than guessed.
        for (chunk.code.items) |_| chunk.source_map.append(self.allocator, .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 }) catch return error.OutOfMemory;
        chunk.strings.appendSlice(self.allocator, template.strings.items) catch return error.OutOfMemory;
        chunk.formats.appendSlice(self.allocator, template.formats.items) catch return error.OutOfMemory;
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
    fn execute(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!Value {
        chunk.verify() catch return error.InvalidInstruction;
        state_helpers.clearFrames(self);
        state_helpers.clearClosures(self);
        self.frames[0] = .{ .return_ip = 0, .base = 0 };
        self.frame_top = 0;
        self.pub_printed = false;
        self.stack_top = 0;
        state_helpers.clearContainers(self);
        state_helpers.clearStrings(self);
        self.collector.collect() catch return error.OutOfMemory;
        self.cell_count = 0;
        self.last_exception = Value.nil();
        self.trace_count = 0;
        self.handler_active = false;
        self.handler_stack_top = 0;
        self.handler_frame_top = 0;
        self.handler_trace_count = 0;
        self.fault_ip = 0;
        var ip: usize = 0;
        // Root reconstruction is comparatively expensive. Traced allocation
        // paths perform their own safepoint before allocating, so normal
        // execution only needs periodic polling. Debug sessions retain
        // instruction-precise polling for breakpoints and stepping.
        var safepoint_ticks: u16 = 0;
        while (ip < chunk.code.items.len) : (ip += 1) {
            const collection_ready = self.collector.stress or
                self.collector.live_allocations >= self.collector.collection_threshold;
            if (self.debugger != null or (safepoint_ticks == 0 and collection_ready)) {
                try object_storage.refreshRoots(self);
                self.collector.safepoint() catch return error.OutOfMemory;
                // Allocation sites perform an immediate safepoint. A longer
                // polling interval keeps allocation-free numeric loops from
                // repeatedly rebuilding the full root set.
                safepoint_ticks = 4095;
            } else if (safepoint_ticks > 0) {
                safepoint_ticks -= 1;
            }
            if (self.debugger) |debugger| if (debugger.onInstruction(ip, self.frame_top)) return error.DebuggerPaused;
            self.fault_ip = ip;
            if (self.trace_count > 0) self.trace[self.trace_count - 1].instruction = ip;
            const instruction = chunk.code.items[ip];
            switch (instruction.op) {
                .halt => return if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1],
                .suspend_point => {},
                .constant => try self.push(try integer(instruction.operand)),
                .make_float => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.floats.items.len))) return error.InvalidInstruction;
                    try self.push(Value.fromFloat(chunk.floats.items[@intCast(instruction.operand)]));
                },
                .true_value => try self.push(Value.fromBool(true)),
                .false_value => try self.push(Value.fromBool(false)),
                .none_value => try self.push(Value.nil()),
                .make_string => {
                    try string_construction.string(RuntimeError, self, instruction.operand, chunk.strings.items);
                },
                .make_format => {
                    try string_construction.format(RuntimeError, self, instruction.operand, chunk.formats.items);
                },
                .make_function => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
                    try self.push(try makeHandle(.function, @intCast(instruction.operand)));
                },
                .make_instance => {
                    try construction.instance(RuntimeError, self, instruction.operand, chunk.classes.items.len);
                },
                .get_property => {
                    try collection_access.getProperty(RuntimeError, self, instruction.operand);
                },
                .set_property => {
                    try collection_access.setProperty(RuntimeError, self, instruction.operand);
                },
                .load_local => {
                    try frame_access.loadLocal(RuntimeError, self, instruction.operand);
                },
                .store_local => {
                    try frame_access.storeLocal(RuntimeError, self, instruction.operand);
                },
                .load_capture => {
                    try frame_access.loadCapture(RuntimeError, self, instruction.operand);
                },
                .load_capture_ref => {
                    try frame_access.loadCaptureRef(RuntimeError, self, instruction.operand);
                },
                .store_capture => {
                    try frame_access.storeCapture(RuntimeError, self, instruction.operand);
                },
                .make_closure => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
                    const function_index: usize = @intCast(instruction.operand);
                    const count = chunk.functions.items[function_index].capture_count;
                    if (self.stack_top < count) return error.StackUnderflow;
                    const slot = try object_storage.newClosure(self, function_index, count);
                    for (0..count) |capture| {
                        const value = self.stack[self.stack_top - count + capture];
                        if (value.handleKind() == .cell) {
                            self.closures[slot].captures[capture] = value;
                        } else {
                            const cell = try object_storage.newCell(self, value);
                            self.closures[slot].captures[capture] = try makeHandle(.cell, cell);
                        }
                    }
                    self.stack_top -= count;
                    try self.push(try makeHandle(.closure, slot));
                },
                .box_dynamic, .unbox_integer, .guard_integer => {},
                .make_array, .make_tuple, .make_set => {
                    try construction.collection(RuntimeError, self, instruction.operand, instruction.op == .make_tuple, instruction.op == .make_set);
                },
                .make_dict => {
                    try construction.dictionary(RuntimeError, self, instruction.operand);
                },
                .index => {
                    try collection_access.index(RuntimeError, self);
                },
                .slice => {
                    try slicing.slice(RuntimeError, self);
                },
                .store_index => {
                    try collection_mutation.storeIndex(RuntimeError, self);
                },
                .length => {
                    try value_operations.length(RuntimeError, self);
                },
                .iterable => {
                    try value_operations.iterable(RuntimeError, self);
                },
                .type_query => {
                    try value_operations.typeQuery(RuntimeError, self);
                },
                .string_lower, .string_upper, .string_strip => {
                    const operation: string_operations.Transform = if (instruction.op == .string_lower) .lower else if (instruction.op == .string_upper) .upper else .strip;
                    try string_operations.transform(RuntimeError, self, operation);
                },
                .string_find => {
                    try string_operations.find(RuntimeError, self);
                },
                .string_replace => {
                    try string_operations.replace(RuntimeError, self);
                },
                .string_split => {
                    try string_operations.split(RuntimeError, self);
                },
                .string_join => {
                    try string_operations.join(RuntimeError, self);
                },
                .append_collection => {
                    try collection_mutation.append(RuntimeError, self);
                },
                .insert_collection => {
                    try collection_mutation.insert(RuntimeError, self);
                },
                .remove_collection => {
                    try collection_mutation.remove(RuntimeError, self);
                },
                .contains_collection => {
                    try collection_mutation.contains(RuntimeError, self);
                },
                .clear_collection => {
                    try collection_mutation.clear(RuntimeError, self);
                },
                .pop_collection => {
                    try collection_mutation.pop(RuntimeError, self);
                },
                .count_collection => {
                    try collection_mutation.count(RuntimeError, self);
                },
                .reverse_collection, .sort_collection => {
                    try collection_mutation.reverseOrSort(RuntimeError, self, instruction.op == .reverse_collection);
                },
                .dict_get, .dict_contains => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const key = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    const slot = dictSlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.dict_count) return error.InvalidInstruction;
                    const result = collections.get(self.dicts[slot], key);
                    self.stack[self.stack_top - 2] = if (instruction.op == .dict_contains) Value.fromBool(result != null) else result orelse return error.InvalidInstruction;
                    self.stack_top -= 1;
                },
                .dict_put => {
                    try collection_mutation.dictPut(RuntimeError, self);
                },
                .dict_remove => {
                    try collection_mutation.dictRemove(RuntimeError, self);
                },
                .dict_keys, .dict_values, .dict_items => {
                    try collection_views.dictView(RuntimeError, self, instruction.op);
                },
                .set_union, .set_intersection, .set_difference => {
                    try collection_mutation.setOperation(RuntimeError, self, instruction.op == .set_union, instruction.op == .set_intersection);
                },
                .range_condition => {
                    try range_operations.condition(RuntimeError, self);
                },
                .range_step => {
                    try range_operations.step(RuntimeError, self, instruction.operand);
                },
                .dup => {
                    try stack_operations.duplicate(RuntimeError, self);
                },
                .guard_float => try stack_operations.guardFloat(RuntimeError, self),
                .guard_boolean => {
                    try stack_operations.guardBoolean(RuntimeError, self);
                },
                .guard_string => {
                    try stack_operations.guardString(RuntimeError, self);
                },
                .raise_value => {
                    try exceptions.raiseValue(RuntimeError, self, &ip, chunk.code.items.len);
                },
                .print => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack_top -= 1;
                    if (value.handleKind() == .string) {
                        const slot = value.handleIndex().?;
                        if (slot >= self.strings.items.len) return error.InvalidInstruction;
                        std.debug.print("{s}\n", .{self.strings.items[slot].bytes});
                    } else if (value.isInt()) std.debug.print("{d}\n", .{value.asInt()}) else if (value.isBool()) std.debug.print("{s}\n", .{if (value.asBool()) "true" else "false"}) else if (value.isFloat()) std.debug.print("{d}\n", .{value.asFloat()}) else std.debug.print("<{s}>\n", .{if (value.handleKind()) |kind| @tagName(kind) else "none"});
                    self.pub_printed = true;
                },
                .pop => {
                    try stack_operations.discard(RuntimeError, self);
                },
                .add => try arithmetic_operations.binary(RuntimeError, self, .add, &ip),
                .subtract => try arithmetic_operations.binary(RuntimeError, self, .subtract, &ip),
                .multiply => try arithmetic_operations.binary(RuntimeError, self, .multiply, &ip),
                .divide => try arithmetic_operations.binary(RuntimeError, self, .divide, &ip),
                .modulo => {
                    if (try arithmetic_operations.modulo(RuntimeError, self, &ip)) continue;
                },
                .negate => {
                    try stack_operations.negate(RuntimeError, self);
                },
                .not => {
                    try stack_operations.logicalNot(RuntimeError, self);
                },
                .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => try arithmetic_operations.compare(RuntimeError, self, instruction.op, &ip),
                .jump_if_false => {
                    try control_flow.jumpIfFalse(RuntimeError, self, instruction.operand, &ip, chunk.code.items.len);
                },
                .jump => {
                    try control_flow.jump(RuntimeError, instruction.operand, &ip, chunk.code.items.len);
                },
                .try_begin => {
                    try exceptions.begin(RuntimeError, self, instruction.operand, chunk.code.items.len);
                },
                .try_end => exceptions.end(self),
                .call => self.call(chunk, instruction.operand, &ip) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .call_method => self.callMethod(chunk, instruction.operand, &ip) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .call_super => self.callSuper(chunk, instruction.operand, &ip) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .call_value => self.callValue(chunk, instruction.operand, &ip) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .return_value => {
                    if (try control_flow.returnValue(RuntimeError, self, &ip)) |value| return value;
                },
            }
        }
        return if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1];
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
