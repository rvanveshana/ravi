const bytecode = @import("ravi_bytecode");
const collections = @import("ravi_vm_collections");
const object_storage = @import("object_storage.zig");
const value_runtime = @import("value_runtime.zig");

pub fn dictView(comptime Error: type, self: anytype, operation: bytecode.OpCode) Error!void {
    if (self.stack_top == 0) return error.InvalidInstruction;
    const handle = self.stack[self.stack_top - 1];
    const dict_slot = value_runtime.dictSlot(handle) orelse return error.InvalidInstruction;
    if (dict_slot >= self.dict_count) return error.InvalidInstruction;
    const array_slot = try object_storage.newArray(self);
    for (0..self.dicts[dict_slot].capacity()) |index| if (self.dicts[dict_slot].occupied[index]) {
        if (operation == .dict_keys) {
            try collections.append(self.arrays[array_slot], self.dicts[dict_slot].keys[index]);
        } else if (operation == .dict_values) {
            try collections.append(self.arrays[array_slot], self.dicts[dict_slot].values[index]);
        } else {
            const pair_slot = try object_storage.newArray(self);
            try collections.append(self.arrays[pair_slot], self.dicts[dict_slot].keys[index]);
            try collections.append(self.arrays[pair_slot], self.dicts[dict_slot].values[index]);
            try collections.append(self.arrays[array_slot], try value_runtime.makeHandle(.array, pair_slot));
        }
    };
    self.stack[self.stack_top - 1] = try value_runtime.makeHandle(.array, array_slot);
}
