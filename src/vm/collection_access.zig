const collections = @import("ravi_vm_collections");
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
        const value = collections.get(self.dicts[slot], key) orelse return error.InvalidInstruction;
        try state_helpers.push(self, value);
    } else if (value_runtime.arraySlot(handle)) |slot| {
        const position = try value_runtime.requireInteger(key);
        if (slot >= self.array_count or position < 0 or @as(usize, @intCast(position)) >= self.arrays[slot].len) return error.InvalidInstruction;
        try state_helpers.push(self, self.arrays[slot].items[@intCast(position)]);
    } else return error.InvalidInstruction;
}
