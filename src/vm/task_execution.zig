const bytecode = @import("ravi_bytecode");
const Value = @import("ravi_vm_value").Value;
const state_helpers = @import("state_helpers.zig");
const execution = @import("execution.zig");

pub fn executeFunction(self: anytype, chunk: *const bytecode.Chunk, function_index: usize, args: []const Value) !Value {
    chunk.verify() catch return error.InvalidInstruction;
    if (function_index >= chunk.functions.items.len) return error.InvalidFunction;
    const function = chunk.functions.items[function_index];
    if (args.len > function.arity) return error.InvalidFunction;
    state_helpers.clearFrames(self);
    state_helpers.clearClosures(self);
    self.frames[0] = .{ .return_ip = 0, .base = 0 };
    self.frame_top = 1;
    self.frames[1] = .{ .return_ip = chunk.code.items.len - 1, .base = 0 };
    try self.frames[1].ensureLocals(self.allocator, function.arity);
    self.stack_top = 0;
    for (args, 0..) |argument, index| {
        try state_helpers.push(self, argument);
        self.frames[1].locals[index] = argument;
    }
    for (args.len..function.arity) |index| self.frames[1].locals[index] = if (function.defaults[index]) |default| Value.fromInt(default) else Value.nil();
    self.collector.collect() catch return error.OutOfMemory;
    self.cell_count = 0;
    self.last_exception = Value.nil();
    self.trace_count = 0;
    self.handler_active = false;
    self.fault_ip = 0;
    return switch (try execution.executeInternal(self, chunk, null, function.entry, null, false)) {
        .completed => |value| value,
        .suspended => return error.InvalidInstruction,
    };
}
