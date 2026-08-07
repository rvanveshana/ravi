const std = @import("std");
const collections = @import("ravi_vm_collections");
const object_storage = @import("object_storage.zig");
const state_helpers = @import("state_helpers.zig");
const string_runtime = @import("strings.zig");
const value_runtime = @import("value_runtime.zig");

pub fn slice(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 3) return error.StackUnderflow;
    const finish = self.stack[self.stack_top - 1];
    const begin = self.stack[self.stack_top - 2];
    const handle = self.stack[self.stack_top - 3];
    self.stack_top -= 3;
    const begin_index = try value_runtime.requireInteger(begin);
    const finish_index = try value_runtime.requireInteger(finish);
    const start: usize = if (begin_index < 0) 0 else @intCast(begin_index);
    if (handle.handleKind() == .string) {
        const text = self.stringSlice(handle) orelse return error.InvalidIndex;
        const start_byte = string_runtime.offset(text, start) orelse return error.InvalidIndex;
        const end_index: usize = if (finish_index < 0) std.math.maxInt(usize) else @intCast(finish_index);
        const end_byte = if (end_index == std.math.maxInt(usize)) text.len else (string_runtime.offset(text, end_index) orelse if (end_index == string_runtime.length(text)) text.len else return error.InvalidIndex);
        if (start_byte > end_byte) return error.InvalidIndex;
        try state_helpers.push(self, try state_helpers.internString(self, text[start_byte..end_byte]));
    } else if (value_runtime.arraySlot(handle)) |slot| {
        if (slot >= self.array_count) return error.InvalidIndex;
        const end: usize = if (finish_index < 0) self.arrays[slot].len else @intCast(finish_index);
        if (start > end or end > self.arrays[slot].len) return error.InvalidIndex;
        const result = try object_storage.newArray(self);
        for (self.arrays[slot].items[start..end]) |value| try collections.append(self.arrays[result], value);
        try state_helpers.push(self, try value_runtime.makeHandle(.array, result));
    } else return error.InvalidIndex;
}
