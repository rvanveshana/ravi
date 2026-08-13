const collections = @import("ravi_vm_collections");
const object_storage = @import("object_storage.zig");
const state_helpers = @import("state_helpers.zig");
const value_runtime = @import("value_runtime.zig");
const Value = @import("ravi_vm_value").Value;

pub fn instance(comptime Error: type, self: anytype, operand: i64, class_count: usize) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(class_count))) return error.InvalidFunction;
    const slot = try object_storage.newInstance(self, @intCast(operand));
    try state_helpers.push(self, try value_runtime.makeHandle(.instance, slot));
}

pub fn collection(comptime Error: type, self: anytype, operand: i64, is_tuple: bool, is_set: bool) Error!void {
    if (operand < 0 or self.stack_top < @as(usize, @intCast(operand))) return error.InvalidInstruction;
    const count: usize = @intCast(operand);
    const slot = try object_storage.newArray(self);
    for (0..count) |index| {
        const value = self.stack[self.stack_top - count + index];
        if (is_set) try collections.appendUnique(self.arrays[slot], value) else try collections.append(self.arrays[slot], value);
    }
    self.stack_top -= count;
    const kind: Value.ObjectKind = if (is_tuple) .tuple else if (is_set) .set else .array;
    try state_helpers.push(self, try value_runtime.makeHandle(kind, slot));
}

pub fn dictionary(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0) return error.InvalidInstruction;
    const count: usize = @intCast(operand);
    if (count > self.stack_top / 2) return error.InvalidInstruction;
    const slot = self.dict_count;
    _ = try object_storage.newDict(self);
    for (0..count) |index| {
        try collections.put(self.dicts[slot], self.stack[self.stack_top - count * 2 + index * 2], self.stack[self.stack_top - count * 2 + index * 2 + 1]);
    }
    self.stack_top -= count * 2;
    try state_helpers.push(self, try value_runtime.makeHandle(.dictionary, slot));
}
