const std = @import("std");
const collections = @import("ravi_vm_collections");
const object_storage = @import("object_storage.zig");
const state_helpers = @import("state_helpers.zig");
const value_runtime = @import("value_runtime.zig");

pub const Transform = enum { lower, upper, strip };

pub fn transform(comptime Error: type, self: anytype, operation: Transform) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    if (handle.handleKind() != .string) return error.InvalidInstruction;
    const source_slot = handle.handleIndex().?;
    if (source_slot >= self.strings.items.len) return error.InvalidInstruction;
    const source_text = self.strings.items[source_slot].bytes;
    var first: usize = 0;
    var last = source_text.len;
    if (operation == .strip) {
        while (first < last and std.ascii.isWhitespace(source_text[first])) first += 1;
        while (last > first and std.ascii.isWhitespace(source_text[last - 1])) last -= 1;
    }
    const result_len = last - first;
    const transformed = try self.allocator.alloc(u8, result_len);
    defer self.allocator.free(transformed);
    for (0..result_len) |index| {
        const value = source_text[first + index];
        transformed[index] = if (operation == .lower) std.ascii.toLower(value) else if (operation == .upper) std.ascii.toUpper(value) else value;
    }
    self.stack[self.stack_top - 1] = try state_helpers.internString(self, transformed);
}

pub fn find(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const haystack = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
    const needle = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
    self.stack[self.stack_top - 2] = try value_runtime.integer(if (std.mem.indexOf(u8, haystack, needle)) |position| @intCast(position) else -1);
    self.stack_top -= 1;
}

pub fn replace(comptime Error: type, self: anytype) Error!void {
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
    self.stack[self.stack_top - 3] = try state_helpers.internString(self, output[0..out]);
    self.stack_top -= 2;
}

pub fn split(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.InvalidInstruction;
    const source = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
    const delimiter = self.stringSlice(self.stack[self.stack_top - 1]) orelse return error.InvalidInstruction;
    if (delimiter.len == 0) return error.InvalidInstruction;
    const array_slot = try object_storage.newArray(self);
    var cursor: usize = 0;
    while (cursor <= source.len) {
        const end = if (std.mem.indexOfPos(u8, source, cursor, delimiter)) |position| position else source.len;
        try collections.append(self.arrays[array_slot], try state_helpers.internString(self, source[cursor..end]));
        if (end == source.len) break;
        cursor = end + delimiter.len;
    }
    self.stack[self.stack_top - 2] = try value_runtime.makeHandle(.array, array_slot);
    self.stack_top -= 1;
}

pub fn join(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const delimiter = self.stringSlice(self.stack[self.stack_top - 2]) orelse return error.InvalidInstruction;
    const handle = self.stack[self.stack_top - 1];
    const array_slot = value_runtime.arraySlot(handle) orelse return error.InvalidInstruction;
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
    self.stack[self.stack_top - 2] = try state_helpers.internString(self, output[0..out]);
    self.stack_top -= 1;
}
