const collections = @import("ravi_vm_collections");
const object_storage = @import("object_storage.zig");
const type_helpers = @import("type_helpers.zig");
const value_runtime = @import("value_runtime.zig");

pub fn length(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    if (handle.handleKind() == .string) {
        const slot = handle.handleIndex().?;
        if (slot >= self.strings.items.len) return error.InvalidInstruction;
        self.stack[self.stack_top - 1] = try value_runtime.integer(@intCast(@import("strings.zig").length(self.strings.items[slot].bytes)));
    } else if (value_runtime.arraySlot(handle)) |slot| {
        if (slot >= self.array_count) return error.InvalidInstruction;
        self.stack[self.stack_top - 1] = try value_runtime.integer(@intCast(self.arrays[slot].len));
    } else if (handle.handleKind() == .dictionary) {
        const slot = handle.handleIndex().?;
        if (slot >= self.dict_count) return error.InvalidInstruction;
        self.stack[self.stack_top - 1] = try value_runtime.integer(@intCast(self.dicts[slot].len));
    } else return error.InvalidInstruction;
}

pub fn iterable(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - 1];
    if (value_runtime.dictSlot(handle)) |dict_slot| {
        if (dict_slot >= self.dict_count) return error.InvalidInstruction;
        const array_slot = try object_storage.newArray(self);
        for (0..self.dicts[dict_slot].capacity()) |index| if (self.dicts[dict_slot].occupied[index]) {
            try collections.append(self.arrays[array_slot], self.dicts[dict_slot].keys[index]);
        };
        self.stack[self.stack_top - 1] = try value_runtime.makeHandle(.array, array_slot);
    } else if (value_runtime.arraySlot(handle) != null or handle.handleKind() == .string) {} else if (handle.isInt()) {
        // A bare integer denotes the shorthand `for x in n:` count, so it is
        // materialized here as the equivalent 0..n-1 sequence.
        const count = handle.asInt();
        if (count < 0) return error.InvalidInstruction;
        const array_slot = try object_storage.newArray(self);
        var value: i64 = 0;
        while (value < count) : (value += 1) try collections.append(self.arrays[array_slot], try value_runtime.integer(value));
        self.stack[self.stack_top - 1] = try value_runtime.makeHandle(.array, array_slot);
    } else return error.InvalidInstruction;
}

pub fn typeQuery(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    self.stack[self.stack_top - 1] = try value_runtime.integer(@intFromEnum(type_helpers.classify(value)));
}
