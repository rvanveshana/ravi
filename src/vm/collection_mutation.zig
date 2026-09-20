const collections = @import("ravi_vm_collections");
const object_storage = @import("object_storage.zig");
const state_helpers = @import("state_helpers.zig");
const value_runtime = @import("value_runtime.zig");
const Value = @import("ravi_vm_value").Value;

pub fn storeIndex(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 3) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const key = self.stack[self.stack_top - 2];
    const handle = self.stack[self.stack_top - 3];
    if (handle.handleKind() == .dictionary) {
        const slot = handle.handleIndex().?;
        if (slot >= self.dict_count) return error.InvalidInstruction;
        try collections.put(self.dicts[slot], key, value);
        try object_storage.writeBarrierValue(self, handle, value);
    } else if (value_runtime.arraySlot(handle)) |slot| {
        const position = try value_runtime.requireInteger(key);
        if (slot >= self.array_count or position < 0 or @as(usize, @intCast(position)) >= self.arrays[slot].len) return error.InvalidIndex;
        self.arrays[slot].items[@intCast(position)] = value;
        try object_storage.writeBarrierValue(self, handle, value);
    } else return error.InvalidInstruction;
    self.stack_top -= 3;
}

pub fn append(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const handle = self.stack[self.stack_top - 2];
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    try collections.append(self.arrays[slot], value);
    self.stack_top -= 2;
}

pub fn insert(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 3) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const position = self.stack[self.stack_top - 2];
    const handle = self.stack[self.stack_top - 3];
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    const index = try value_runtime.requireInteger(position);
    if (index < 0) return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    try collections.insert(self.arrays[slot], @intCast(index), value);
    self.stack_top -= 3;
}

pub fn remove(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const handle = self.stack[self.stack_top - 2];
    if (value_runtime.dictSlot(handle)) |dict_slot| {
        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
        _ = try collections.remove(self.dicts[dict_slot], value);
        self.stack_top -= 2;
        return;
    }
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    var position: ?usize = null;
    for (0..self.arrays[slot].len) |index| if (Value.eql(self.arrays[slot].items[index], value)) {
        position = index;
        break;
    };
    if (position == null) return error.InvalidInstruction;
    _ = try collections.pop(self.arrays[slot], position.?);
    self.stack_top -= 2;
}

pub fn contains(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const handle = self.stack[self.stack_top - 2];
    if (value_runtime.dictSlot(handle)) |dict_slot| {
        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
        self.stack[self.stack_top - 2] = Value.fromBool(collections.get(self.dicts[dict_slot], value) != null);
        self.stack_top -= 1;
        return;
    }
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    self.stack[self.stack_top - 2] = Value.fromBool(collections.contains(self.arrays[slot], value));
    self.stack_top -= 1;
}

pub fn clear(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    collections.clear(self.arrays[slot]);
    self.stack_top -= 1;
}

pub fn pop(comptime Error: type, self: anytype, arguments: i64) Error!void {
    if (arguments == 1) {
        if (self.stack_top < 2) return error.StackUnderflow;
        const key = self.stack[self.stack_top - 1];
        const handle = self.stack[self.stack_top - 2];
        if (handle.handleKind() != .dictionary) return error.InvalidInstruction;
        const slot = handle.handleIndex().?;
        if (slot >= self.dict_count) return error.InvalidInstruction;
        self.stack[self.stack_top - 2] = try collections.remove(self.dicts[slot], key);
        self.stack_top -= 1;
        return;
    }
    if (arguments != 0) return error.InvalidInstruction;
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count or self.arrays[slot].len == 0) return error.InvalidIndex;
    self.stack[self.stack_top - 1] = try collections.pop(self.arrays[slot], self.arrays[slot].len - 1);
}

pub fn count(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    self.stack[self.stack_top - 1] = try value_runtime.integer(@intCast(self.arrays[slot].len));
}

pub fn reverseOrSort(comptime Error: type, self: anytype, reverse: bool) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    const slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.array_count) return error.InvalidInstruction;
    if (reverse) collections.reverse(self.arrays[slot]) else collections.sort(self.arrays[slot]);
    self.stack_top -= 1;
}

pub fn dictPut(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 3) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    const key = self.stack[self.stack_top - 2];
    const handle = self.stack[self.stack_top - 3];
    const slot = value_runtime.dictSlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.dict_count) return error.InvalidInstruction;
    try collections.put(self.dicts[slot], key, value);
    try object_storage.writeBarrierValue(self, handle, value);
    self.stack_top -= 3;
}

pub fn dictRemove(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const key = self.stack[self.stack_top - 1];
    const handle = self.stack[self.stack_top - 2];
    const slot = value_runtime.dictSlot(handle) orelse return error.InvalidInstruction;
    if (slot >= self.dict_count) return error.InvalidInstruction;
    _ = try collections.remove(self.dicts[slot], key);
    self.stack_top -= 2;
}

pub fn setOperation(comptime Error: type, self: anytype, is_union: bool, is_intersection: bool) Error!void {
    if (self.stack_top < 2) return error.InvalidInstruction;
    const right = self.stack[self.stack_top - 1];
    const left = self.stack[self.stack_top - 2];
    const left_slot = value_runtime.arraySlot(left) orelse return error.InvalidInstruction;
    const right_slot = value_runtime.arraySlot(right) orelse return error.InvalidInstruction;
    if (left_slot >= self.array_count or right_slot >= self.array_count) return error.InvalidInstruction;
    const result_slot = try object_storage.newArray(self);
    for (self.arrays[left_slot].items[0..self.arrays[left_slot].len]) |value| {
        if (!is_intersection or collections.contains(self.arrays[right_slot], value)) try collections.appendUnique(self.arrays[result_slot], value);
    }
    if (is_union) for (self.arrays[right_slot].items[0..self.arrays[right_slot].len]) |value| try collections.appendUnique(self.arrays[result_slot], value);
    if (!is_union and !is_intersection) {
        self.arrays[result_slot].len = 0;
        for (self.arrays[left_slot].items[0..self.arrays[left_slot].len]) |value| if (!collections.contains(self.arrays[right_slot], value)) try collections.appendUnique(self.arrays[result_slot], value);
    }
    self.stack[self.stack_top - 2] = try value_runtime.makeHandle(.set, result_slot);
    self.stack_top -= 1;
}

comptime {
    _ = state_helpers.push;
}
