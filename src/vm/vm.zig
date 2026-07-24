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
            self.debugger == null and dispatch.FastDispatcher.supports(decoded)) {
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
                .make_string => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.strings.items.len))) return error.InvalidInstruction;
                    const raw = chunk.strings.items[@intCast(instruction.operand)];
                    if (raw.len < 2) return error.InvalidInstruction;
                    const quote = raw[0];
                    const start: usize = if (raw.len >= 6 and raw[0] == quote and raw[1] == quote and raw[2] == quote) 3 else 1;
                    const trim: usize = if (start == 3) 3 else 1;
                    if (raw.len < start + trim) return error.InvalidInstruction;
                    const decoded = try self.allocator.alloc(u8, raw.len - start - trim);
                    defer self.allocator.free(decoded);
                    var out: usize = 0;
                    var cursor = start;
                    const end = raw.len - trim;
                    while (cursor < end) : (cursor += 1) {
                        if (raw[cursor] == '\\' and cursor + 1 < end) {
                            cursor += 1;
                            decoded[out] = switch (raw[cursor]) {
                                'n' => '\n',
                                'r' => '\r',
                                't' => '\t',
                                '\\' => '\\',
                                '\'' => '\'',
                                '"' => '"',
                                else => raw[cursor],
                            };
                        } else {
                            decoded[out] = raw[cursor];
                        }
                        out += 1;
                    }
                    try self.push(try self.internString(decoded[0..out]));
                },
                .make_function => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
                    try self.push(try makeHandle(.function, @intCast(instruction.operand)));
                },
                .make_instance => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.classes.items.len))) return error.InvalidFunction;
                    const slot = try object_storage.newInstance(self, @intCast(instruction.operand));
                    self.instance_count += 1;
                    try self.push(try makeHandle(.instance, slot));
                },
                .get_property => {
                    if (self.stack_top == 0 or instruction.operand < 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    const slot = instanceSlot(handle) orelse return error.InvalidFunction;
                    if (slot >= self.instance_count) return error.InvalidFunction;
                    self.stack[self.stack_top - 1] = collections.get(&self.instances[slot].fields, try integer(instruction.operand)) orelse return error.MissingKey;
                },
                .set_property => {
                    if (self.stack_top < 2 or instruction.operand < 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 2];
                    const value = self.stack[self.stack_top - 1];
                    const slot = instanceSlot(handle) orelse return error.InvalidFunction;
                    if (slot >= self.instance_count) return error.InvalidFunction;
                    try collections.put(&self.instances[slot].fields, try integer(instruction.operand), value);
                    try object_storage.writeBarrierValue(self, handle, value);
                    self.stack_top -= 2;
                },
                .load_local => {
                    if (instruction.operand < 0 or instruction.operand >= self.frames[self.frame_top].locals.len) return error.InvalidLocal;
                    try self.push(self.frames[self.frame_top].locals[@intCast(instruction.operand)]);
                },
                .store_local => {
                    if (instruction.operand < 0 or self.stack_top == 0) return error.InvalidLocal;
                    try self.frames[self.frame_top].ensureLocals(self.allocator, @as(usize, @intCast(instruction.operand)) + 1);
                    self.frames[self.frame_top].locals[@intCast(instruction.operand)] = self.stack[self.stack_top - 1];
                },
                .load_capture => {
                    if (instruction.operand < 0 or instruction.operand >= self.frames[self.frame_top].captures.len) return error.InvalidLocal;
                    const captured = self.frames[self.frame_top].captures[@intCast(instruction.operand)];
                    if (captured.handleKind() == .cell) {
                        const cell = captured.handleIndex().?;
                        if (cell >= self.cell_count) return error.InvalidLocal;
                        try self.push(self.cells[cell].value);
                    } else try self.push(captured);
                },
                .load_capture_ref => {
                    if (instruction.operand < 0 or instruction.operand >= self.frames[self.frame_top].captures.len) return error.InvalidLocal;
                    try self.push(self.frames[self.frame_top].captures[@intCast(instruction.operand)]);
                },
                .store_capture => {
                    if (instruction.operand < 0 or instruction.operand >= self.frames[self.frame_top].captures.len or self.stack_top == 0) return error.InvalidLocal;
                    const capture = self.frames[self.frame_top].captures[@intCast(instruction.operand)];
                    if (capture.handleKind() != .cell) return error.InvalidLocal;
                    const cell = capture.handleIndex().?;
                    if (cell >= self.cell_count) return error.InvalidLocal;
                    self.cells[cell].value = self.stack[self.stack_top - 1];
                    try object_storage.writeBarrierValue(self, capture, self.stack[self.stack_top - 1]);
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
                    if (instruction.operand < 0 or self.stack_top < @as(usize, @intCast(instruction.operand))) return error.InvalidInstruction;
                    const count: usize = @intCast(instruction.operand);
                    const slot = try object_storage.newArray(self);
                    for (0..count) |i| {
                        const value = self.stack[self.stack_top - count + i];
                        if (instruction.op == .make_set) try collections.appendUnique(self.arrays[slot], value) else try collections.append(self.arrays[slot], value);
                    }
                    self.stack_top -= count;
                    const kind: Value.ObjectKind = if (instruction.op == .make_tuple) .tuple else if (instruction.op == .make_set) .set else .array;
                    try self.push(try makeHandle(kind, slot));
                },
                .make_dict => {
                    if (instruction.operand < 0) return error.InvalidInstruction;
                    const count: usize = @intCast(instruction.operand);
                    if (count > self.stack_top / 2) return error.InvalidInstruction;
                    const slot = self.dict_count;
                    _ = try object_storage.newDict(self);
                    self.dict_count += 1;
                    for (0..count) |i| {
                        try collections.put(self.dicts[slot], self.stack[self.stack_top - count * 2 + i * 2], self.stack[self.stack_top - count * 2 + i * 2 + 1]);
                    }
                    self.stack_top -= count * 2;
                    try self.push(try makeHandle(.dictionary, slot));
                },
                .index => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const key = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    self.stack_top -= 2;
                    if (handle.handleKind() == .string) {
                        const slot = handle.handleIndex().?;
                        const position = try requireInteger(key);
                        if (slot >= self.strings.items.len or position < 0) return error.InvalidIndex;
                        const codepoint = string_runtime.at(self.strings.items[slot].bytes, @intCast(position)) orelse return error.InvalidIndex;
                        try self.push(try integer(codepoint));
                    } else if (handle.handleKind() == .dictionary) {
                        const slot = handle.handleIndex().?;
                        if (slot >= self.dict_count) return error.InvalidInstruction;
                        const value = collections.get(self.dicts[slot], key) orelse return error.InvalidInstruction;
                        try self.push(value);
                    } else if (arraySlot(handle)) |slot| {
                        const position = try requireInteger(key);
                        if (slot >= self.array_count or position < 0 or @as(usize, @intCast(position)) >= self.arrays[slot].len) return error.InvalidInstruction;
                        try self.push(self.arrays[slot].items[@intCast(position)]);
                    } else return error.InvalidInstruction;
                },
                .slice => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const finish = self.stack[self.stack_top - 1];
                    const begin = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    self.stack_top -= 3;
                    const begin_index = try requireInteger(begin);
                    const finish_index = try requireInteger(finish);
                    const start: usize = if (begin_index < 0) 0 else @intCast(begin_index);
                    if (handle.handleKind() == .string) {
                        const text = self.stringSlice(handle) orelse return error.InvalidIndex;
                        const start_byte = string_runtime.offset(text, start) orelse return error.InvalidIndex;
                        const end_index: usize = if (finish_index < 0) std.math.maxInt(usize) else @intCast(finish_index);
                        const end_byte = if (end_index == std.math.maxInt(usize)) text.len else (string_runtime.offset(text, end_index) orelse if (end_index == string_runtime.length(text)) text.len else return error.InvalidIndex);
                        if (start_byte > end_byte) return error.InvalidIndex;
                        try self.push(try self.internString(text[start_byte..end_byte]));
                    } else if (arraySlot(handle)) |slot| {
                        if (slot >= self.array_count) return error.InvalidIndex;
                        const end: usize = if (finish_index < 0) self.arrays[slot].len else @intCast(finish_index);
                        if (start > end or end > self.arrays[slot].len) return error.InvalidIndex;
                        const result = try object_storage.newArray(self);
                        for (self.arrays[slot].items[start..end]) |value| try collections.append(self.arrays[result], value);
                        try self.push(try makeHandle(.array, result));
                    } else return error.InvalidIndex;
                },
                .store_index => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const key = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    if (handle.handleKind() == .dictionary) {
                        const slot = handle.handleIndex().?;
                        if (slot >= self.dict_count) return error.InvalidInstruction;
                        try collections.put(self.dicts[slot], key, value);
                        try object_storage.writeBarrierValue(self, handle, value);
                    } else if (arraySlot(handle)) |slot| {
                        const position = try requireInteger(key);
                        if (slot >= self.array_count or position < 0 or @as(usize, @intCast(position)) >= self.arrays[slot].len) return error.InvalidIndex;
                        self.arrays[slot].items[@intCast(position)] = value;
                        try object_storage.writeBarrierValue(self, handle, value);
                    } else return error.InvalidInstruction;
                    self.stack_top -= 3;
                },
                .length => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle.handleKind() == .string) {
                        const slot = handle.handleIndex().?;
                        if (slot >= self.strings.items.len) return error.InvalidInstruction;
                        self.stack[self.stack_top - 1] = try integer(@intCast(string_runtime.length(self.strings.items[slot].bytes)));
                    } else if (arraySlot(handle)) |slot| {
                        if (slot >= self.array_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 1] = try integer(@intCast(self.arrays[slot].len));
                    } else if (handle.handleKind() == .dictionary) {
                        const slot = handle.handleIndex().?;
                        if (slot >= self.dict_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 1] = try integer(@intCast(self.dicts[slot].len));
                    } else return error.InvalidInstruction;
                },
                .type_query => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack[self.stack_top - 1] = try integer(@intFromEnum(type_helpers.classify(value)));
                },
                .string_lower, .string_upper, .string_strip => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle.handleKind() != .string) return error.InvalidInstruction;
                    const source_slot = handle.handleIndex().?;
                    if (source_slot >= self.strings.items.len) return error.InvalidInstruction;
                    const source_text = self.strings.items[source_slot].bytes;
                    var first: usize = 0;
                    var last = source_text.len;
                    if (instruction.op == .string_strip) {
                        while (first < last and std.ascii.isWhitespace(source_text[first])) first += 1;
                        while (last > first and std.ascii.isWhitespace(source_text[last - 1])) last -= 1;
                    }
                    const result_len = last - first;
                    const transformed = try self.allocator.alloc(u8, result_len);
                    defer self.allocator.free(transformed);
                    for (0..result_len) |i| {
                        const value = source_text[first + i];
                        transformed[i] = if (instruction.op == .string_lower) std.ascii.toLower(value) else if (instruction.op == .string_upper) std.ascii.toUpper(value) else value;
                    }
                    self.stack[self.stack_top - 1] = try self.internString(transformed);
                },
                .string_find => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const haystack = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const needle = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
                    self.stack[self.stack_top - 2] = try integer(if (std.mem.indexOf(u8, haystack, needle)) |position| @intCast(position) else -1);
                    self.stack_top -= 1;
                },
                .string_replace => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const source = self.stringSlice(self.stack[self.stack_top - 3]) orelse return error.InvalidInstruction;
                    const old = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const replacement = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
                    if (old.len == 0) return error.InvalidInstruction;
                    var output: [256]u8 = undefined;
                    var out: usize = 0;
                    var cursor: usize = 0;
                    while (cursor < source.len) {
                        if (std.mem.startsWith(u8, source[cursor..], old)) {
                            if (out + replacement.len > output.len) return error.StringTooLong;
                            @memcpy(output[out .. out + replacement.len], replacement);
                            out += replacement.len;
                            cursor += old.len;
                        } else {
                            if (out == output.len) return error.StringTooLong;
                            output[out] = source[cursor];
                            out += 1;
                            cursor += 1;
                        }
                    }
                    self.stack[self.stack_top - 3] = try self.internString(output[0..out]);
                    self.stack_top -= 2;
                },
                .string_split => {
                    if (self.stack_top < 2) return error.InvalidInstruction;
                    const source = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const delimiter = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
                    if (delimiter.len == 0) return error.InvalidInstruction;
                    const array_slot = try object_storage.newArray(self);
                    var cursor: usize = 0;
                    while (cursor <= source.len) {
                        const end = if (std.mem.indexOfPos(u8, source, cursor, delimiter)) |position| position else source.len;
                        try collections.append(self.arrays[array_slot], try self.internString(source[cursor..end]));
                        if (end == source.len) break;
                        cursor = end + delimiter.len;
                    }
                    self.stack[self.stack_top - 2] = try makeHandle(.array, array_slot);
                    self.stack_top -= 1;
                },
                .string_join => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const delimiter = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const handle = self.stack[self.stack_top - 1];
                    const array_slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (array_slot >= self.array_count) return error.InvalidInstruction;
                    var output: [256]u8 = undefined;
                    var out: usize = 0;
                    for (self.arrays[array_slot].items[0..self.arrays[array_slot].len], 0..) |item, index| {
                        const part = self.stringSlice(item) orelse return error.InvalidInstruction;
                        if (index > 0) {
                            if (out + delimiter.len > output.len) return error.StringTooLong;
                            @memcpy(output[out .. out + delimiter.len], delimiter);
                            out += delimiter.len;
                        }
                        if (out + part.len > output.len) return error.StringTooLong;
                        @memcpy(output[out .. out + part.len], part);
                        out += part.len;
                    }
                    self.stack[self.stack_top - 2] = try self.internString(output[0..out]);
                    self.stack_top -= 1;
                },
                .append_collection => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    try collections.append(self.arrays[slot], value);
                    self.stack_top -= 2;
                },
                .insert_collection => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const position = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    const index = try requireInteger(position);
                    if (index < 0) return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    try collections.insert(self.arrays[slot], @intCast(index), value);
                    self.stack_top -= 3;
                },
                .remove_collection => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (dictSlot(handle)) |dict_slot| {
                        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
                        _ = try collections.remove(self.dicts[dict_slot], value);
                        self.stack_top -= 2;
                        continue;
                    }
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    var position: ?usize = null;
                    for (0..self.arrays[slot].len) |i| if (Value.eql(self.arrays[slot].items[i], value)) {
                        position = i;
                        break;
                    };
                    if (position == null) return error.InvalidInstruction;
                    _ = try collections.pop(self.arrays[slot], position.?);
                    self.stack_top -= 2;
                },
                .contains_collection => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (dictSlot(handle)) |dict_slot| {
                        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 2] = Value.fromBool(collections.get(self.dicts[dict_slot], value) != null);
                        self.stack_top -= 1;
                        continue;
                    }
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    self.stack[self.stack_top - 2] = Value.fromBool(collections.contains(self.arrays[slot], value));
                    self.stack_top -= 1;
                },
                .clear_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    collections.clear(self.arrays[slot]);
                    self.stack_top -= 1;
                },
                .pop_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count or self.arrays[slot].len == 0) return error.InvalidIndex;
                    self.stack[self.stack_top - 1] = try collections.pop(self.arrays[slot], self.arrays[slot].len - 1);
                },
                .count_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    self.stack[self.stack_top - 1] = try integer(@intCast(self.arrays[slot].len));
                },
                .reverse_collection, .sort_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    const slot = arraySlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    if (instruction.op == .reverse_collection) collections.reverse(self.arrays[slot]) else collections.sort(self.arrays[slot]);
                    self.stack_top -= 1;
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
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const key = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    const slot = dictSlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.dict_count) return error.InvalidInstruction;
                    try collections.put(self.dicts[slot], key, value);
                    try object_storage.writeBarrierValue(self, handle, value);
                    self.stack_top -= 3;
                },
                .dict_remove => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const key = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    const slot = dictSlot(handle) orelse return error.InvalidInstruction;
                    if (slot >= self.dict_count) return error.InvalidInstruction;
                    _ = try collections.remove(self.dicts[slot], key);
                    self.stack_top -= 2;
                },
                .dict_keys, .dict_values, .dict_items => {
                    if (self.stack_top == 0) return error.InvalidInstruction;
                    const handle = self.stack[self.stack_top - 1];
                    const dict_slot = dictSlot(handle) orelse return error.InvalidInstruction;
                    if (dict_slot >= self.dict_count) return error.InvalidInstruction;
                    const array_slot = try object_storage.newArray(self);
                    for (0..self.dicts[dict_slot].capacity()) |i| if (self.dicts[dict_slot].occupied[i]) {
                        if (instruction.op == .dict_keys or instruction.op == .dict_items) try collections.append(self.arrays[array_slot], self.dicts[dict_slot].keys[i]);
                        if (instruction.op == .dict_values) try collections.append(self.arrays[array_slot], self.dicts[dict_slot].values[i]);
                        if (instruction.op == .dict_items) try collections.append(self.arrays[array_slot], self.dicts[dict_slot].values[i]);
                    };
                    self.stack[self.stack_top - 1] = try makeHandle(.array, array_slot);
                },
                .set_union, .set_intersection, .set_difference => {
                    if (self.stack_top < 2) return error.InvalidInstruction;
                    const right = self.stack[self.stack_top - 1];
                    const left = self.stack[self.stack_top - 2];
                    const left_slot = arraySlot(left) orelse return error.InvalidInstruction;
                    const right_slot = arraySlot(right) orelse return error.InvalidInstruction;
                    if (left_slot >= self.array_count or right_slot >= self.array_count) return error.InvalidInstruction;
                    const result_slot = try object_storage.newArray(self);
                    for (self.arrays[left_slot].items[0..self.arrays[left_slot].len]) |value| {
                        if (instruction.op != .set_intersection or collections.contains(self.arrays[right_slot], value)) try collections.appendUnique(self.arrays[result_slot], value);
                    }
                    if (instruction.op == .set_union) for (self.arrays[right_slot].items[0..self.arrays[right_slot].len]) |value| try collections.appendUnique(self.arrays[result_slot], value);
                    if (instruction.op == .set_difference) {
                        self.arrays[result_slot].len = 0;
                        for (self.arrays[left_slot].items[0..self.arrays[left_slot].len]) |value| if (!collections.contains(self.arrays[right_slot], value)) try collections.appendUnique(self.arrays[result_slot], value);
                    }
                    self.stack[self.stack_top - 2] = try makeHandle(.set, result_slot);
                    self.stack_top -= 1;
                },
                .range_condition => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const step = self.stack[self.stack_top - 1];
                    const limit = self.stack[self.stack_top - 2];
                    const current = self.stack[self.stack_top - 3];
                    // Numeric ranges are the hottest general loop path. Keep
                    // the fully dynamic fallback, but avoid repeated helper
                    // calls and error construction when tags already prove
                    // all operands are integers.
                    const step_value: i64 = if (step.isInt()) step.asInt() else try requireInteger(step);
                    const limit_value: i64 = if (limit.isInt()) limit.asInt() else try requireInteger(limit);
                    const current_value: i64 = if (current.isInt()) current.asInt() else try requireInteger(current);
                    self.stack[self.stack_top - 3] = Value.fromBool(if (step_value < 0) current_value > limit_value else current_value < limit_value);
                    self.stack_top -= 2;
                },
                .range_step => {
                    if (instruction.operand < 0) return error.InvalidInstruction;
                    const encoded_slots: u64 = @intCast(instruction.operand);
                    const current_slot: usize = @intCast(encoded_slots >> 32);
                    const step_slot: usize = @intCast(encoded_slots & 0xffffffff);
                    const frame = &self.frames[self.frame_top];
                    if (current_slot >= frame.locals.len or step_slot >= frame.locals.len) return error.InvalidLocal;
                    const current_value = frame.locals[current_slot];
                    const step_value = frame.locals[step_slot];
                    const current = if (current_value.isInt()) current_value.asInt() else try requireInteger(current_value);
                    const step = if (step_value.isInt()) step_value.asInt() else try requireInteger(step_value);
                    frame.locals[current_slot] = try integer(current +| step);
                },
                .dup => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    try self.push(self.stack[self.stack_top - 1]);
                },
                .guard_float => if (self.stack_top == 0 or !self.stack[self.stack_top - 1].isFloat()) return error.TypeGuardFailed,
                .guard_boolean => {
                    if (self.stack_top == 0) return error.TypeGuardFailed;
                    const value = self.stack[self.stack_top - 1];
                    if (!value.isBool() and (!value.isInt() or (value.asInt() != 0 and value.asInt() != 1))) return error.TypeGuardFailed;
                },
                .guard_string => {
                    if (self.stack_top == 0 or self.stack[self.stack_top - 1].handleKind() != .string) return error.TypeGuardFailed;
                },
                .raise_value => {
                    // An empty raise inside an exception handler rethrows the
                    // active value; outside a handler it remains an error.
                    if (self.stack_top == 0) {
                        if (!self.handler_active or self.last_exception.isNil()) return error.RaisedException;
                    } else self.last_exception = self.stack[self.stack_top - 1];
                    if (!self.handler_active) return error.RaisedException;
                    self.handler_active = false;
                    self.stack_top = self.handler_stack_top;
                    state_helpers.unwindFrames(self, self.handler_frame_top);
                    self.trace_count = self.handler_trace_count;
                    ip = if (self.handler_ip == 0) chunk.code.items.len - 1 else self.handler_ip - 1;
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
                    if (self.stack_top == 0) return error.StackUnderflow;
                    self.stack_top -= 1;
                },
                .add => operators.binary(self, .add) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .subtract => operators.binary(self, .subtract) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .multiply => operators.binary(self, .multiply) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .divide => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const rhs = try requireInteger(self.stack[self.stack_top - 1]);
                    if (rhs == 0) {
                        if (!self.handleFault(&ip)) return error.DivisionByZero;
                        continue;
                    }
                    self.stack[self.stack_top - 2] = try integer(@divTrunc(try requireInteger(self.stack[self.stack_top - 2]), rhs));
                    self.stack_top -= 1;
                },
                .modulo => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const rhs = try requireInteger(self.stack[self.stack_top - 1]);
                    if (rhs == 0) {
                        if (!self.handleFault(&ip)) return error.DivisionByZero;
                        continue;
                    }
                    self.stack[self.stack_top - 2] = try integer(@rem(try requireInteger(self.stack[self.stack_top - 2]), rhs));
                    self.stack_top -= 1;
                },
                .negate => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    self.stack[self.stack_top - 1] = try integer(-(try requireInteger(self.stack[self.stack_top - 1])));
                },
                .not => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    self.stack[self.stack_top - 1] = Value.fromBool(!self.stack[self.stack_top - 1].truthy());
                },
                .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => operators.compare(self, instruction.op) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .jump_if_false => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack_top -= 1;
                    if (!value.truthy()) {
                        if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.code.items.len))) return error.InvalidJump;
                        const target: usize = @intCast(instruction.operand);
                        ip = if (target == 0) chunk.code.items.len - 1 else target - 1;
                    }
                },
                .jump => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.code.items.len))) return error.InvalidJump;
                    const target: usize = @intCast(instruction.operand);
                    ip = if (target == 0) chunk.code.items.len - 1 else target - 1;
                },
                .try_begin => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.code.items.len))) return error.InvalidJump;
                    self.handler_ip = @intCast(instruction.operand);
                    self.handler_stack_top = self.stack_top;
                    self.handler_frame_top = self.frame_top;
                    self.handler_trace_count = self.trace_count;
                    self.handler_active = true;
                },
                .try_end => self.handler_active = false,
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
                    const value = if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1];
                    if (self.frame_top == 0) return value;
                    const old_base = self.frames[self.frame_top].base;
                    const return_ip = self.frames[self.frame_top].return_ip;
                    self.frames[self.frame_top].deinit(self.allocator);
                    self.frame_top -= 1;
                    if (self.trace_count > 0) self.trace_count -= 1;
                    self.stack_top = old_base;
                    try self.push(value);
                    ip = return_ip;
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
    fn stringSlice(self: *const Vm, handle: Value) ?[]const u8 {
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
