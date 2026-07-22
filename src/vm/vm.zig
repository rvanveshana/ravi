const std = @import("std");
const bytecode = @import("ravi_bytecode");
const collections = @import("ravi_vm_collections");
const string_runtime = @import("strings.zig");
const trace_runtime = @import("trace.zig");
const errors = @import("errors.zig");
const frames = @import("frames.zig");
const type_helpers = @import("type_helpers.zig");
const state_helpers = @import("state_helpers.zig");
const call_runtime = @import("call_runtime.zig");
pub const collection_primitives = collections;

pub const RuntimeError = errors.RuntimeError;
pub const RuntimeType = errors.TypeId;
const Frame = frames.Frame;
const Closure = frames.Closure;
const Cell = frames.Cell;
pub const TraceFrame = trace_runtime.Frame;
const ArrayValue = collections.Array;
const DictValue = collections.Dict;
pub const Vm = struct {
    stack: [256]i64 = undefined,
    stack_top: usize = 0,
    frames: [32]Frame = undefined,
    frame_top: usize = 0,
    pub_printed: bool = false,
    arrays: [64]ArrayValue = undefined,
    array_count: usize = 0,
    dicts: [32]DictValue = undefined,
    dict_count: usize = 0,
    strings: [64][256]u8 = undefined,
    string_lengths: [64]usize = @splat(0),
    string_count: usize = 0,
    closures: [64]Closure = undefined,
    closure_count: usize = 0,
    cells: [128]Cell = undefined,
    cell_count: usize = 0,
    last_exception: i64 = 0,
    trace: [trace_runtime.Capacity]TraceFrame = undefined,
    trace_count: usize = 0,
    handler_active: bool = false,
    handler_ip: usize = 0,
    pub fn run(self: *Vm, chunk: *const bytecode.Chunk) RuntimeError!i64 {
        chunk.verify() catch return error.InvalidInstruction;
        self.frames[0] = .{ .return_ip = 0, .base = 0 };
        self.frame_top = 0;
        self.pub_printed = false;
        self.stack_top = 0;
        self.array_count = 0;
        self.dict_count = 0;
        self.string_count = 0;
        self.closure_count = 0;
        self.cell_count = 0;
        self.last_exception = 0;
        self.trace_count = 0;
        self.handler_active = false;
        var ip: usize = 0;
        while (ip < chunk.code.items.len) : (ip += 1) {
            const instruction = chunk.code.items[ip];
            switch (instruction.op) {
                .halt => return if (self.stack_top == 0) 0 else self.stack[self.stack_top - 1],
                .constant => try self.push(instruction.operand),
                .make_string => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.strings.items.len)) or self.string_count >= self.strings.len) return error.InvalidInstruction;
                    const raw = chunk.strings.items[@intCast(instruction.operand)];
                    const quote = raw[0];
                    const start: usize = if (raw.len >= 6 and raw[0] == quote and raw[1] == quote and raw[2] == quote) 3 else 1;
                    const trim: usize = if (start == 3) 3 else 1;
                    if (raw.len < start + trim or raw.len - start - trim > 255) return error.StringTooLong;
                    var out: usize = 0;
                    var cursor = start;
                    const end = raw.len - trim;
                    while (cursor < end) : (cursor += 1) {
                        if (raw[cursor] == '\\' and cursor + 1 < end) cursor += 1;
                        self.strings[self.string_count][out] = raw[cursor];
                        out += 1;
                    }
                    self.string_lengths[self.string_count] = out;
                    var existing_handle: ?i64 = null;
                    for (0..self.string_count) |existing| if (self.string_lengths[existing] == out and std.mem.eql(u8, self.strings[existing][0..out], self.strings[self.string_count][0..out])) {
                        existing_handle = -@as(i64, @intCast(2000 + existing));
                        break;
                    };
                    if (existing_handle) |existing| {
                        try self.push(existing);
                        continue;
                    }
                    const handle = -@as(i64, @intCast(2000 + self.string_count));
                    self.string_count += 1;
                    try self.push(handle);
                },
                .make_function => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
                    try self.push(-@as(i64, @intCast(3000 + instruction.operand)));
                },
                .load_local => {
                    if (instruction.operand < 0 or instruction.operand >= 64) return error.InvalidLocal;
                    try self.push(self.frames[self.frame_top].locals[@intCast(instruction.operand)]);
                },
                .store_local => {
                    if (instruction.operand < 0 or instruction.operand >= 64 or self.stack_top == 0) return error.InvalidLocal;
                    self.frames[self.frame_top].locals[@intCast(instruction.operand)] = self.stack[self.stack_top - 1];
                },
                .load_capture => {
                    if (instruction.operand < 0 or instruction.operand >= 64) return error.InvalidLocal;
                    if (instruction.operand >= self.frames[self.frame_top].capture_count) return error.InvalidLocal;
                    const captured = self.frames[self.frame_top].captures[@intCast(instruction.operand)];
                    try self.push(if (captured <= -5000) self.cells[@intCast(-captured - 5000)].value else captured);
                },
                .load_capture_ref => {
                    if (instruction.operand < 0 or instruction.operand >= self.frames[self.frame_top].capture_count) return error.InvalidLocal;
                    try self.push(self.frames[self.frame_top].captures[@intCast(instruction.operand)]);
                },
                .store_capture => {
                    if (instruction.operand < 0 or instruction.operand >= self.frames[self.frame_top].capture_count or self.stack_top == 0) return error.InvalidLocal;
                    const capture = self.frames[self.frame_top].captures[@intCast(instruction.operand)];
                    if (capture > -5000) return error.InvalidLocal;
                    const cell = @as(usize, @intCast(-capture - 5000));
                    if (cell >= self.cell_count) return error.InvalidLocal;
                    self.cells[cell].value = self.stack[self.stack_top - 1];
                },
                .make_closure => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len)) or self.closure_count >= self.closures.len) return error.InvalidFunction;
                    const function_index: usize = @intCast(instruction.operand);
                    const count = chunk.functions.items[function_index].capture_count;
                    if (count > 64 or self.stack_top < count) return error.StackUnderflow;
                    const slot = self.closure_count;
                    self.closure_count += 1;
                    self.closures[slot] = .{ .function_index = function_index, .capture_count = count };
                    for (0..count) |capture| {
                        const value = self.stack[self.stack_top - count + capture];
                        if (value <= -5000) {
                            self.closures[slot].captures[capture] = value;
                        } else {
                            if (self.cell_count >= self.cells.len) return error.InvalidFunction;
                            const cell = self.cell_count;
                            self.cell_count += 1;
                            self.cells[cell] = .{ .value = value };
                            self.closures[slot].captures[capture] = -@as(i64, @intCast(5000 + cell));
                        }
                    }
                    self.stack_top -= count;
                    try self.push(-@as(i64, @intCast(4000 + slot)));
                },
                .box_dynamic, .unbox_integer, .guard_integer => {},
                .make_array, .make_tuple, .make_set => {
                    if (instruction.operand < 0 or instruction.operand > 64 or self.stack_top < @as(usize, @intCast(instruction.operand)) or self.array_count >= self.arrays.len) return error.InvalidInstruction;
                    const count: usize = @intCast(instruction.operand);
                    const slot = self.array_count;
                    self.array_count += 1;
                    self.arrays[slot].len = 0;
                    for (0..count) |i| {
                        const value = self.stack[self.stack_top - count + i];
                        if (instruction.op == .make_set) try collections.appendUnique(&self.arrays[slot], value) else self.arrays[slot].items[i] = value;
                    }
                    if (instruction.op != .make_set) self.arrays[slot].len = count;
                    self.stack_top -= count;
                    const handle: i64 = -@as(i64, @intCast(slot + 1));
                    try self.push(handle);
                },
                .make_dict => {
                    const count: usize = @intCast(instruction.operand);
                    if (count > 32 or self.stack_top < count * 2 or self.dict_count >= self.dicts.len) return error.InvalidInstruction;
                    const slot = self.dict_count;
                    self.dict_count += 1;
                    for (0..count) |i| {
                        try collections.put(&self.dicts[slot], self.stack[self.stack_top - count * 2 + i * 2], self.stack[self.stack_top - count * 2 + i * 2 + 1]);
                    }
                    self.stack_top -= count * 2;
                    try self.push(-@as(i64, @intCast(1000 + slot + 1)));
                },
                .index => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const key = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (handle >= 0 or handle == std.math.minInt(i64)) return error.InvalidInstruction;
                    self.stack_top -= 2;
                    if (handle <= -2000) {
                        const slot: usize = @intCast(-handle - 2000);
                        if (slot >= self.string_count or key < 0) return error.InvalidIndex;
                        const codepoint = string_runtime.at(self.strings[slot][0..self.string_lengths[slot]], @intCast(key)) orelse return error.InvalidIndex;
                        try self.push(codepoint);
                        continue;
                    }
                    if (handle <= -1001) {
                        const slot: usize = @intCast(-handle - 1001);
                        if (slot >= self.dict_count) return error.InvalidInstruction;
                        const value = collections.get(&self.dicts[slot], key) orelse return error.InvalidInstruction;
                        try self.push(value);
                    } else {
                        const slot: usize = @intCast(-handle - 1);
                        if (slot >= self.array_count or key < 0 or @as(usize, @intCast(key)) >= self.arrays[slot].len) return error.InvalidInstruction;
                        try self.push(self.arrays[slot].items[@intCast(key)]);
                    }
                },
                .slice => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const finish = self.stack[self.stack_top - 1];
                    const begin = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    self.stack_top -= 3;
                    const start: usize = if (begin < 0) 0 else @intCast(begin);
                    if (handle <= -2000) {
                        const text = self.stringSlice(handle) orelse return error.InvalidIndex;
                        const start_byte = string_runtime.offset(text, start) orelse return error.InvalidIndex;
                        const end_index: usize = if (finish < 0) std.math.maxInt(usize) else @intCast(finish);
                        const end_byte = if (end_index == std.math.maxInt(usize)) text.len else (string_runtime.offset(text, end_index) orelse if (end_index == string_runtime.length(text)) text.len else return error.InvalidIndex);
                        if (start_byte > end_byte) return error.InvalidIndex;
                        try self.push(try self.internString(text[start_byte..end_byte]));
                    } else if (handle < 0) {
                        const slot: usize = @intCast(-handle - 1);
                        if (slot >= self.array_count) return error.InvalidIndex;
                        const end: usize = if (finish < 0) self.arrays[slot].len else @intCast(finish);
                        if (start > end or end > self.arrays[slot].len or self.array_count >= self.arrays.len) return error.InvalidIndex;
                        const result = self.array_count;
                        self.array_count += 1;
                        self.arrays[result].len = 0;
                        for (self.arrays[slot].items[start..end]) |value| try collections.append(&self.arrays[result], value);
                        try self.push(-@as(i64, @intCast(result + 1)));
                    } else return error.InvalidIndex;
                },
                .store_index => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const key = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    if (handle >= 0) return error.InvalidInstruction;
                    if (handle <= -1000 and handle > -2000) {
                        const slot: usize = @intCast(-handle - 1001);
                        if (slot >= self.dict_count) return error.InvalidInstruction;
                        try collections.put(&self.dicts[slot], key, value);
                    } else if (handle > -1000) {
                        const slot: usize = @intCast(-handle - 1);
                        if (slot >= self.array_count or key < 0 or @as(usize, @intCast(key)) >= self.arrays[slot].len) return error.InvalidIndex;
                        self.arrays[slot].items[@intCast(key)] = value;
                    } else return error.InvalidInstruction;
                    self.stack_top -= 3;
                },
                .length => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle <= -2000) {
                        const slot: usize = @intCast(-handle - 2000);
                        if (slot >= self.string_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 1] = @intCast(self.string_lengths[slot]);
                    } else if (handle >= -1000) {
                        const slot: usize = @intCast(-handle - 1);
                        if (slot >= self.array_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 1] = @intCast(self.arrays[slot].len);
                    } else {
                        const slot: usize = @intCast(-handle - 1001);
                        if (slot >= self.dict_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 1] = @intCast(self.dicts[slot].len);
                    }
                },
                .type_query => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack[self.stack_top - 1] = @intFromEnum(type_helpers.classify(value));
                },
                .string_lower, .string_upper, .string_strip => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle > -2000) return error.InvalidInstruction;
                    const source_slot: usize = @intCast(-handle - 2000);
                    if (source_slot >= self.string_count or self.string_count >= self.strings.len) return error.InvalidInstruction;
                    var first: usize = 0;
                    var last = self.string_lengths[source_slot];
                    if (instruction.op == .string_strip) {
                        while (first < last and std.ascii.isWhitespace(self.strings[source_slot][first])) first += 1;
                        while (last > first and std.ascii.isWhitespace(self.strings[source_slot][last - 1])) last -= 1;
                    }
                    const result_slot = self.string_count;
                    const result_len = last - first;
                    for (0..result_len) |i| {
                        const value = self.strings[source_slot][first + i];
                        self.strings[result_slot][i] = if (instruction.op == .string_lower) std.ascii.toLower(value) else if (instruction.op == .string_upper) std.ascii.toUpper(value) else value;
                    }
                    self.string_lengths[result_slot] = result_len;
                    self.string_count += 1;
                    self.stack[self.stack_top - 1] = -@as(i64, @intCast(2000 + result_slot));
                },
                .string_find => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const haystack = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const needle = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
                    self.stack[self.stack_top - 2] = if (std.mem.indexOf(u8, haystack, needle)) |position| @intCast(position) else -1;
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
                    if (self.stack_top < 2 or self.array_count >= self.arrays.len) return error.InvalidInstruction;
                    const source = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const delimiter = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
                    if (delimiter.len == 0) return error.InvalidInstruction;
                    const array_slot = self.array_count;
                    self.array_count += 1;
                    self.arrays[array_slot].len = 0;
                    var cursor: usize = 0;
                    while (cursor <= source.len) {
                        const end = if (std.mem.indexOfPos(u8, source, cursor, delimiter)) |position| position else source.len;
                        try collections.append(&self.arrays[array_slot], try self.internString(source[cursor..end]));
                        if (end == source.len) break;
                        cursor = end + delimiter.len;
                    }
                    self.stack[self.stack_top - 2] = -@as(i64, @intCast(array_slot + 1));
                    self.stack_top -= 1;
                },
                .string_join => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const delimiter = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle >= 0 or handle <= -1000) return error.InvalidInstruction;
                    const array_slot: usize = @intCast(-handle - 1);
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
                    if (handle >= 0 or handle <= -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    try collections.append(&self.arrays[slot], value);
                    self.stack_top -= 2;
                },
                .insert_collection => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const position = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    if (handle >= 0 or handle <= -1000 or position < 0) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    try collections.insert(&self.arrays[slot], @intCast(position), value);
                    self.stack_top -= 3;
                },
                .remove_collection => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (handle >= 0) return error.InvalidInstruction;
                    if (handle <= -1000) {
                        const dict_slot: usize = @intCast(-handle - 1001);
                        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
                        _ = try collections.remove(&self.dicts[dict_slot], value);
                        self.stack_top -= 2;
                        continue;
                    }
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    var position: ?usize = null;
                    for (0..self.arrays[slot].len) |i| if (self.arrays[slot].items[i] == value) {
                        position = i;
                        break;
                    };
                    if (position == null) return error.InvalidInstruction;
                    _ = try collections.pop(&self.arrays[slot], position.?);
                    self.stack_top -= 2;
                },
                .contains_collection => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (handle >= 0) return error.InvalidInstruction;
                    if (handle <= -1000) {
                        const dict_slot: usize = @intCast(-handle - 1001);
                        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
                        self.stack[self.stack_top - 2] = @intFromBool(collections.get(&self.dicts[dict_slot], value) != null);
                        self.stack_top -= 1;
                        continue;
                    }
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    self.stack[self.stack_top - 2] = @intFromBool(collections.contains(&self.arrays[slot], value));
                    self.stack_top -= 1;
                },
                .clear_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle >= 0 or handle <= -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    collections.clear(&self.arrays[slot]);
                    self.stack_top -= 1;
                },
                .pop_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle >= 0 or handle <= -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count or self.arrays[slot].len == 0) return error.InvalidIndex;
                    self.stack[self.stack_top - 1] = try collections.pop(&self.arrays[slot], self.arrays[slot].len - 1);
                },
                .count_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle >= 0 or handle <= -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    self.stack[self.stack_top - 1] = @intCast(self.arrays[slot].len);
                },
                .reverse_collection, .sort_collection => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle >= 0 or handle <= -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1);
                    if (slot >= self.array_count) return error.InvalidInstruction;
                    if (instruction.op == .reverse_collection) collections.reverse(&self.arrays[slot]) else collections.sort(&self.arrays[slot]);
                    self.stack_top -= 1;
                },
                .dict_get, .dict_contains => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const key = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (handle > -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1001);
                    if (slot >= self.dict_count) return error.InvalidInstruction;
                    const result = collections.get(&self.dicts[slot], key);
                    self.stack[self.stack_top - 2] = if (instruction.op == .dict_contains) @intFromBool(result != null) else result orelse return error.InvalidInstruction;
                    self.stack_top -= 1;
                },
                .dict_put => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    const key = self.stack[self.stack_top - 2];
                    const handle = self.stack[self.stack_top - 3];
                    if (handle > -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1001);
                    if (slot >= self.dict_count) return error.InvalidInstruction;
                    try collections.put(&self.dicts[slot], key, value);
                    self.stack_top -= 3;
                },
                .dict_remove => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const key = self.stack[self.stack_top - 1];
                    const handle = self.stack[self.stack_top - 2];
                    if (handle > -1000) return error.InvalidInstruction;
                    const slot: usize = @intCast(-handle - 1001);
                    if (slot >= self.dict_count) return error.InvalidInstruction;
                    _ = try collections.remove(&self.dicts[slot], key);
                    self.stack_top -= 2;
                },
                .dict_keys, .dict_values, .dict_items => {
                    if (self.stack_top == 0 or self.array_count >= self.arrays.len) return error.InvalidInstruction;
                    const handle = self.stack[self.stack_top - 1];
                    if (handle > -1000) return error.InvalidInstruction;
                    const dict_slot: usize = @intCast(-handle - 1001);
                    if (dict_slot >= self.dict_count) return error.InvalidInstruction;
                    const array_slot = self.array_count;
                    self.array_count += 1;
                    self.arrays[array_slot].len = 0;
                    for (0..collections.DictCapacity) |i| if (self.dicts[dict_slot].occupied[i]) {
                        if (instruction.op == .dict_keys or instruction.op == .dict_items) try collections.append(&self.arrays[array_slot], self.dicts[dict_slot].keys[i]);
                        if (instruction.op == .dict_values) try collections.append(&self.arrays[array_slot], self.dicts[dict_slot].values[i]);
                        if (instruction.op == .dict_items) try collections.append(&self.arrays[array_slot], self.dicts[dict_slot].values[i]);
                    };
                    self.stack[self.stack_top - 1] = -@as(i64, @intCast(array_slot + 1));
                },
                .set_union, .set_intersection, .set_difference => {
                    if (self.stack_top < 2 or self.array_count >= self.arrays.len) return error.InvalidInstruction;
                    const right = self.stack[self.stack_top - 1];
                    const left = self.stack[self.stack_top - 2];
                    if (left >= 0 or right >= 0 or left <= -1000 or right <= -1000) return error.InvalidInstruction;
                    const left_slot: usize = @intCast(-left - 1);
                    const right_slot: usize = @intCast(-right - 1);
                    if (left_slot >= self.array_count or right_slot >= self.array_count) return error.InvalidInstruction;
                    const result_slot = self.array_count;
                    self.array_count += 1;
                    self.arrays[result_slot].len = 0;
                    for (self.arrays[left_slot].items[0..self.arrays[left_slot].len]) |value| {
                        if (instruction.op != .set_intersection or collections.contains(&self.arrays[right_slot], value)) try collections.appendUnique(&self.arrays[result_slot], value);
                    }
                    if (instruction.op == .set_union) for (self.arrays[right_slot].items[0..self.arrays[right_slot].len]) |value| try collections.appendUnique(&self.arrays[result_slot], value);
                    if (instruction.op == .set_difference) {
                        self.arrays[result_slot].len = 0;
                        for (self.arrays[left_slot].items[0..self.arrays[left_slot].len]) |value| if (!collections.contains(&self.arrays[right_slot], value)) try collections.appendUnique(&self.arrays[result_slot], value);
                    }
                    self.stack[self.stack_top - 2] = -@as(i64, @intCast(result_slot + 1));
                    self.stack_top -= 1;
                },
                .range_condition => {
                    if (self.stack_top < 3) return error.StackUnderflow;
                    const step = self.stack[self.stack_top - 1];
                    const limit = self.stack[self.stack_top - 2];
                    const current = self.stack[self.stack_top - 3];
                    self.stack[self.stack_top - 3] = if (step < 0) @intFromBool(current > limit) else @intFromBool(current < limit);
                    self.stack_top -= 2;
                },
                .dup => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    try self.push(self.stack[self.stack_top - 1]);
                },
                .guard_float => return error.TypeGuardFailed,
                .guard_boolean => {
                    if (self.stack_top == 0 or (self.stack[self.stack_top - 1] != 0 and self.stack[self.stack_top - 1] != 1)) return error.TypeGuardFailed;
                },
                .guard_string => {
                    if (self.stack_top == 0 or self.stack[self.stack_top - 1] > -2000) return error.TypeGuardFailed;
                },
                .raise_value => {
                    if (self.stack_top == 0) return error.RaisedException;
                    self.last_exception = self.stack[self.stack_top - 1];
                    if (!self.handler_active) return error.RaisedException;
                    self.handler_active = false;
                    ip = if (self.handler_ip == 0) chunk.code.items.len - 1 else self.handler_ip - 1;
                },
                .print => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack_top -= 1;
                    if (value <= -2000) {
                        const slot: usize = @intCast(-value - 2000);
                        if (slot >= self.string_count) return error.InvalidInstruction;
                        std.debug.print("{s}\n", .{self.strings[slot][0..self.string_lengths[slot]]});
                    } else std.debug.print("{d}\n", .{value});
                    self.pub_printed = true;
                },
                .pop => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    self.stack_top -= 1;
                },
                .add => self.binary(.add) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .subtract => self.binary(.subtract) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .multiply => self.binary(.multiply) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .divide => {
                    if (self.stack_top < 2) return error.StackUnderflow;
                    const rhs = self.stack[self.stack_top - 1];
                    if (rhs == 0) {
                        if (!self.handleFault(&ip)) return error.DivisionByZero;
                        continue;
                    }
                    self.stack[self.stack_top - 2] = @divTrunc(self.stack[self.stack_top - 2], rhs);
                    self.stack_top -= 1;
                },
                .negate => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    self.stack[self.stack_top - 1] = -self.stack[self.stack_top - 1];
                },
                .not => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    self.stack[self.stack_top - 1] = @intFromBool(self.stack[self.stack_top - 1] == 0);
                },
                .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => self.compare(instruction.op) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .jump_if_false => {
                    if (self.stack_top == 0) return error.StackUnderflow;
                    const value = self.stack[self.stack_top - 1];
                    self.stack_top -= 1;
                    if (value == 0) {
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
                    self.handler_active = true;
                },
                .try_end => self.handler_active = false,
                .call => self.call(chunk, instruction.operand, &ip) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .call_value => self.callValue(chunk, instruction.operand, &ip) catch |err| {
                    if (!self.handleFault(&ip)) return err;
                },
                .return_value => {
                    const value = if (self.stack_top == 0) 0 else self.stack[self.stack_top - 1];
                    if (self.frame_top == 0) return value;
                    const old_base = self.frames[self.frame_top].base;
                    const return_ip = self.frames[self.frame_top].return_ip;
                    self.frame_top -= 1;
                    self.stack_top = old_base;
                    try self.push(value);
                    ip = return_ip;
                },
            }
        }
        return if (self.stack_top == 0) 0 else self.stack[self.stack_top - 1];
    }
    fn push(self: *Vm, value: i64) RuntimeError!void {
        return state_helpers.push(self, value);
    }
    fn handleFault(self: *Vm, ip: *usize) bool {
        return state_helpers.handleFault(self, ip);
    }
    fn stringSlice(self: *const Vm, handle: i64) ?[]const u8 {
        if (handle > -2000) return null;
        const slot: usize = @intCast(-handle - 2000);
        if (slot >= self.string_count) return null;
        return self.strings[slot][0..self.string_lengths[slot]];
    }
    fn internString(self: *Vm, text: []const u8) RuntimeError!i64 {
        return state_helpers.internString(self, text);
    }
    fn call(self: *Vm, chunk: *const bytecode.Chunk, operand: i64, ip: *usize) RuntimeError!void {
        return call_runtime.call(self, chunk, operand, ip);
    }

    fn callValue(self: *Vm, chunk: *const bytecode.Chunk, arity_operand: i64, ip: *usize) RuntimeError!void {
        return call_runtime.callValue(self, chunk, arity_operand, ip);
    }

    fn binary(self: *Vm, op: bytecode.OpCode) RuntimeError!void {
        if (self.stack_top < 2) return error.StackUnderflow;
        const rhs = self.stack[self.stack_top - 1];
        const lhs = self.stack[self.stack_top - 2];
        if (op == .add and lhs <= -2000 and rhs <= -2000) {
            const left_slot: usize = @intCast(-lhs - 2000);
            const right_slot: usize = @intCast(-rhs - 2000);
            if (left_slot >= self.string_count or right_slot >= self.string_count) return error.InvalidInstruction;
            if (self.string_count >= self.strings.len) return error.StringTooLong;
            const result_slot = self.string_count;
            const left_len = self.string_lengths[left_slot];
            const right_len = self.string_lengths[right_slot];
            if (left_len + right_len > 255) return error.StringTooLong;
            @memcpy(self.strings[result_slot][0..left_len], self.strings[left_slot][0..left_len]);
            @memcpy(self.strings[result_slot][left_len .. left_len + right_len], self.strings[right_slot][0..right_len]);
            self.string_lengths[result_slot] = left_len + right_len;
            self.string_count += 1;
            self.stack[self.stack_top - 2] = -@as(i64, @intCast(2000 + result_slot));
            self.stack_top -= 1;
            return;
        }
        self.stack[self.stack_top - 2] = switch (op) {
            .add => lhs + rhs,
            .subtract => lhs - rhs,
            .multiply => lhs * rhs,
            else => return error.InvalidInstruction,
        };
        self.stack_top -= 1;
    }
    fn compare(self: *Vm, op: bytecode.OpCode) RuntimeError!void {
        if (self.stack_top < 2) return error.StackUnderflow;
        const rhs = self.stack[self.stack_top - 1];
        const lhs = self.stack[self.stack_top - 2];
        if ((op == .equal or op == .not_equal) and lhs <= -2000 and rhs <= -2000) {
            const left_slot: usize = @intCast(-lhs - 2000);
            const right_slot: usize = @intCast(-rhs - 2000);
            if (left_slot >= self.string_count or right_slot >= self.string_count) return error.InvalidInstruction;
            const same = self.string_lengths[left_slot] == self.string_lengths[right_slot] and std.mem.eql(u8, self.strings[left_slot][0..self.string_lengths[left_slot]], self.strings[right_slot][0..self.string_lengths[right_slot]]);
            self.stack[self.stack_top - 2] = @intFromBool(if (op == .equal) same else !same);
            self.stack_top -= 1;
            return;
        }
        self.stack[self.stack_top - 2] = switch (op) {
            .equal => @intFromBool(lhs == rhs),
            .not_equal => @intFromBool(lhs != rhs),
            .less => @intFromBool(lhs < rhs),
            .less_equal => @intFromBool(lhs <= rhs),
            .greater => @intFromBool(lhs > rhs),
            .greater_equal => @intFromBool(lhs >= rhs),
            .logic_and => @intFromBool(lhs != 0 and rhs != 0),
            .logic_or => @intFromBool(lhs != 0 or rhs != 0),
            else => return error.InvalidInstruction,
        };
        self.stack_top -= 1;
    }
};
