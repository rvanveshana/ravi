const std = @import("std");
const collections = @import("ravi_vm_collections");
const Value = @import("ravi_vm_value").Value;
const object_storage = @import("object_storage.zig");
const string_runtime = @import("strings.zig");
const state_helpers = @import("state_helpers.zig");
const value_runtime = @import("value_runtime.zig");

pub fn getProperty(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (self.stack_top == 0 or operand < 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    const slot = value_runtime.instanceSlot(handle) orelse return error.InvalidFunction;
    if (slot >= self.instance_count) return error.InvalidFunction;
    self.stack[self.stack_top - 1] = collections.get(&self.instances[slot].fields, try value_runtime.integer(operand)) orelse return error.MissingKey;
}

pub fn setProperty(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (self.stack_top < 2 or operand < 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 2];
    const value = self.stack[self.stack_top - 1];
    const slot = value_runtime.instanceSlot(handle) orelse return error.InvalidFunction;
    if (slot >= self.instance_count) return error.InvalidFunction;
    try collections.put(&self.instances[slot].fields, try value_runtime.integer(operand), value);
    try object_storage.writeBarrierValue(self, handle, value);
    self.stack_top -= 2;
}

pub fn index(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const key = self.stack[self.stack_top - 1];
    const handle = self.stack[self.stack_top - 2];
    self.stack_top -= 2;
    if (handle.handleKind() == .string) {
        const slot = handle.handleIndex().?;
        const position = try value_runtime.requireInteger(key);
        if (slot >= self.strings.items.len or position < 0) return error.InvalidIndex;
        const codepoint = string_runtime.at(self.strings.items[slot].bytes, @intCast(position)) orelse return error.InvalidIndex;
        try state_helpers.push(self, try value_runtime.integer(codepoint));
    } else if (handle.handleKind() == .dictionary) {
        const slot = handle.handleIndex().?;
        if (slot >= self.dict_count) return error.InvalidInstruction;
        const value = if (key.handleKind() == .string) blk: {
            const requested = self.stringSlice(key) orelse return error.InvalidInstruction;
            var found: ?Value = null;
            for (self.dicts[slot].occupied, 0..) |occupied, dict_index| if (occupied) {
                const candidate = self.dicts[slot].keys[dict_index];
                if (candidate.handleKind() == .string and std.mem.eql(u8, self.stringSlice(candidate) orelse return error.InvalidInstruction, requested)) {
                    found = self.dicts[slot].values[dict_index];
                    break;
                }
            };
            break :blk found;
        } else collections.get(self.dicts[slot], key);
        const result = value orelse return error.InvalidInstruction;
        try state_helpers.push(self, result);
    } else if (value_runtime.arraySlot(handle)) |slot| {
        const position = try value_runtime.requireInteger(key);
        if (slot >= self.array_count or position < 0 or @as(usize, @intCast(position)) >= self.arrays[slot].len) return error.InvalidInstruction;
        try state_helpers.push(self, self.arrays[slot].items[@intCast(position)]);
    } else return error.InvalidInstruction;
}
