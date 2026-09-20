const std = @import("std");
const bytecode = @import("ravi_bytecode");
const collections = @import("ravi_vm_collections");
const RuntimeError = @import("errors.zig").RuntimeError;
const Value = @import("ravi_vm_value").Value;
const state_helpers = @import("state_helpers.zig");
const call_runtime = @import("call_runtime.zig");
const object_storage = @import("object_storage.zig");
const value_runtime = @import("value_runtime.zig");
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
const async_state = @import("ravi_async_state");
const sleepMilliseconds = @import("sleep.zig").sleepMilliseconds;
const integer = value_runtime.integer;
const makeHandle = value_runtime.makeHandle;
const dictSlot = value_runtime.dictSlot;

pub const ResumableResult = union(enum) { suspended: Value, completed: Value };
pub fn execute(self: anytype, chunk: *const bytecode.Chunk) RuntimeError!Value {
    return switch (try executeInternal(self, chunk, null, 0, null, true)) {
        .completed => |value| value,
        .suspended => unreachable,
    };
}

pub fn executeResumable(self: anytype, chunk: *const bytecode.Chunk, machine: *async_state.Machine, next_ip: *usize, reset: bool) RuntimeError!ResumableResult {
    return executeInternal(self, chunk, machine, next_ip.*, next_ip, reset);
}

pub fn executeInternal(self: anytype, chunk: *const bytecode.Chunk, machine: ?*async_state.Machine, ip_start: usize, next_ip: ?*usize, reset: bool) RuntimeError!ResumableResult {
    chunk.verify() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidInstruction;
    if (reset) {
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
    }
    var ip: usize = ip_start;
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
        const instruction_result: RuntimeError!void = blk: {
            switch (instruction.op) {
                .halt => {
                    const value = if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1];
                    if (machine) |state| state.complete(value) catch |err| return machineError(err);
                    return .{ .completed = value };
                },
                .suspend_point => {
                    if (machine) |state| {
                        const value = if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1];
                        state.yieldValue(ip, @intCast(@max(instruction.operand, 0)), value) catch |err| return machineError(err);
                        if (next_ip) |resume_ip| resume_ip.* = ip + 1;
                        return .{ .suspended = value };
                    }
                },
                .constant => try state_helpers.push(self, try integer(instruction.operand)),
                .make_float => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.floats.items.len))) return error.InvalidInstruction;
                    try state_helpers.push(self, Value.fromFloat(chunk.floats.items[@intCast(instruction.operand)]));
                },
                .true_value => try state_helpers.push(self, Value.fromBool(true)),
                .false_value => try state_helpers.push(self, Value.fromBool(false)),
                .none_value => try state_helpers.push(self, Value.nil()),
                .make_string => try string_construction.string(RuntimeError, self, instruction.operand, chunk.strings.items),
                .make_exception => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const name_value = self.stack[self.stack_top - 1];
                    const name = self.stringSlice(name_value) orelse return error.TypeGuardFailed;
                    const slot = object_storage.newException(self, name) catch return error.OutOfMemory;
                    self.stack_top -= 1;
                    try state_helpers.push(self, Value.fromHandle(.exception, slot) catch return error.InvalidInstruction);
                },
                .make_format => try string_construction.format(RuntimeError, self, instruction.operand, chunk.formats.items),
                .make_function => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
                    try state_helpers.push(self, try makeHandle(.function, @intCast(instruction.operand)));
                },
                .make_instance => try construction.instance(RuntimeError, self, instruction.operand, chunk.classes.items.len),
                .get_property => try collection_access.getProperty(RuntimeError, self, instruction.operand),
                .set_property => try collection_access.setProperty(RuntimeError, self, instruction.operand),
                .load_local => try frame_access.loadLocal(RuntimeError, self, instruction.operand),
                .store_local => try frame_access.storeLocal(RuntimeError, self, instruction.operand),
                .load_capture => try frame_access.loadCapture(RuntimeError, self, instruction.operand),
                .load_capture_ref => try frame_access.loadCaptureRef(RuntimeError, self, instruction.operand),
                .store_capture => try frame_access.storeCapture(RuntimeError, self, instruction.operand),
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
                    try state_helpers.push(self, try makeHandle(.closure, slot));
                },
                .box_dynamic, .unbox_integer, .guard_integer => {},
                .sleep => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const duration = self.stack[self.stack_top - 1];
                    if (!duration.isInt() or duration.asInt() < 0) return error.TypeGuardFailed;
                    const milliseconds: u64 = @intCast(duration.asInt());
                    try sleepMilliseconds(milliseconds);
                    self.stack[self.stack_top - 1] = Value.nil();
                },
                .spawn => {
                    if (instruction.operand < 0) return error.InvalidInstruction;
                    const arity: usize = @intCast(instruction.operand);
                    if (self.stack_top < arity + 1) return error.StackUnderflow;
                    const callee = self.stack[self.stack_top - arity - 1];
                    if (callee.handleKind() != .function) return error.InvalidFunction;
                    const function_index = callee.handleIndex() orelse return error.InvalidFunction;
                    const future = try self.spawnTask(chunk, function_index, self.stack[self.stack_top - arity .. self.stack_top]);
                    self.stack_top -= arity + 1;
                    try state_helpers.push(self, future);
                },
                .wait => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const result = try self.waitTask(self.stack[self.stack_top - 1]);
                    self.stack[self.stack_top - 1] = result;
                },
                .make_array, .make_tuple, .make_set => {
                    try construction.collection(RuntimeError, self, instruction.operand, instruction.op == .make_tuple, instruction.op == .make_set);
                },
                .make_dict => try construction.dictionary(RuntimeError, self, instruction.operand),
                .index => try collection_access.index(RuntimeError, self),
                .slice => try slicing.slice(RuntimeError, self),
                .store_index => try collection_mutation.storeIndex(RuntimeError, self),
                .length => try value_operations.length(RuntimeError, self),
                .iterable => try value_operations.iterable(RuntimeError, self),
                .type_query => try value_operations.typeQuery(RuntimeError, self),
                .string_lower, .string_upper, .string_strip => {
                    const operation: string_operations.Transform = if (instruction.op == .string_lower) .lower else if (instruction.op == .string_upper) .upper else .strip;
                    try string_operations.transform(RuntimeError, self, operation);
                },
                .string_find => try string_operations.find(RuntimeError, self),
                .string_replace => try string_operations.replace(RuntimeError, self),
                .string_split => try string_operations.split(RuntimeError, self),
                .string_join => try string_operations.join(RuntimeError, self),
                .append_collection => try collection_mutation.append(RuntimeError, self),
                .insert_collection => try collection_mutation.insert(RuntimeError, self),
                .remove_collection => try collection_mutation.remove(RuntimeError, self),
                .contains_collection => try collection_mutation.contains(RuntimeError, self),
                .clear_collection => try collection_mutation.clear(RuntimeError, self),
                .pop_collection => try collection_mutation.pop(RuntimeError, self),
                .count_collection => try collection_mutation.count(RuntimeError, self),
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
                .dict_put => try collection_mutation.dictPut(RuntimeError, self),
                .dict_remove => try collection_mutation.dictRemove(RuntimeError, self),
                .dict_keys, .dict_values, .dict_items => try collection_views.dictView(RuntimeError, self, instruction.op),
                .set_union, .set_intersection, .set_difference => {
                    try collection_mutation.setOperation(RuntimeError, self, instruction.op == .set_union, instruction.op == .set_intersection);
                },
                .range_condition => try range_operations.condition(RuntimeError, self),
                .range_step => try range_operations.step(RuntimeError, self, instruction.operand),
                .dup => try stack_operations.duplicate(RuntimeError, self),
                .guard_float => try stack_operations.guardFloat(RuntimeError, self),
                .guard_boolean => try stack_operations.guardBoolean(RuntimeError, self),
                .guard_string => try stack_operations.guardString(RuntimeError, self),
                .raise_value => try exceptions.raiseValue(RuntimeError, self, &ip, chunk.code.items.len),
                .exception_match => try exceptions.matchType(self, chunk),
                .print => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack_top -= 1;
                    if (value.handleKind() == .string) {
                        const slot = value.handleIndex().?;
                        if (slot >= self.strings.items.len) return error.InvalidInstruction;
                        std.debug.print("{s}\n", .{self.strings.items[slot].bytes});
                    } else if (value.isInt()) {
                        std.debug.print("{d}\n", .{value.asInt()});
                    } else if (value.isBool()) {
                        std.debug.print("{s}\n", .{if (value.asBool()) "true" else "false"});
                    } else if (value.isFloat()) {
                        std.debug.print("{d}\n", .{value.asFloat()});
                    } else {
                        std.debug.print("<{s}>\n", .{if (value.handleKind()) |kind| @tagName(kind) else "none"});
                    }
                    self.pub_printed = true;
                },
                .pop => try stack_operations.discard(RuntimeError, self),
                .add => try arithmetic_operations.binary(RuntimeError, self, .add, &ip),
                .subtract => try arithmetic_operations.binary(RuntimeError, self, .subtract, &ip),
                .multiply => try arithmetic_operations.binary(RuntimeError, self, .multiply, &ip),
                .divide => try arithmetic_operations.binary(RuntimeError, self, .divide, &ip),
                .modulo => {
                    if (try arithmetic_operations.modulo(RuntimeError, self, &ip)) continue;
                },
                .negate => try stack_operations.negate(RuntimeError, self),
                .not => try stack_operations.logicalNot(RuntimeError, self),
                .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => try arithmetic_operations.compare(RuntimeError, self, instruction.op, &ip),
                .jump_if_false => try control_flow.jumpIfFalse(RuntimeError, self, instruction.operand, &ip, chunk.code.items.len),
                .jump => try control_flow.jump(RuntimeError, instruction.operand, &ip, chunk.code.items.len),
                .try_begin => try exceptions.begin(RuntimeError, self, instruction.operand, chunk.code.items.len),
                .try_end => exceptions.end(self),
                .call => try doCall(self, .call, chunk, instruction.operand, &ip),
                .call_method => try doCall(self, .call_method, chunk, instruction.operand, &ip),
                .call_super => try doCall(self, .call_super, chunk, instruction.operand, &ip),
                .call_value => try doCall(self, .call_value, chunk, instruction.operand, &ip),
                .return_value => {
                    if (try control_flow.returnValue(RuntimeError, self, &ip)) |value| {
                        if (machine) |state| state.complete(value) catch |err| return machineError(err);
                        return .{ .completed = value };
                    }
                },
            }
            break :blk {};
        };
        instruction_result catch |err| if (!state_helpers.handleFaultWithError(self, &ip, err)) return err;
    }

    const value = if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1];
    if (machine) |state| state.complete(value) catch |err| return machineError(err);
    return .{ .completed = value };
}

fn machineError(err: anyerror) RuntimeError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidInstruction,
    };
}

const CallKind = enum { call, call_method, call_super, call_value };

fn doCall(self: anytype, kind: CallKind, chunk: *const bytecode.Chunk, operand: i64, ip: *usize) RuntimeError!void {
    try state_helpers.ensureCallCapacity(self);
    switch (kind) {
        .call => call_runtime.call(self, chunk, operand, ip) catch |err| if (!state_helpers.handleFaultWithError(self, ip, err)) return err,
        .call_method => call_runtime.callMethod(self, chunk, operand, ip) catch |err| if (!state_helpers.handleFaultWithError(self, ip, err)) return err,
        .call_super => call_runtime.callSuper(self, chunk, operand, ip) catch |err| if (!state_helpers.handleFaultWithError(self, ip, err)) return err,
        .call_value => call_runtime.callValue(self, chunk, operand, ip) catch |err| if (!state_helpers.handleFaultWithError(self, ip, err)) return err,
    }
}
