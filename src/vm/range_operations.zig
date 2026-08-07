const value_runtime = @import("value_runtime.zig");
const Value = @import("ravi_vm_value").Value;

pub fn condition(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top < 3) return error.StackUnderflow;
    const step_value_raw = self.stack[self.stack_top - 1];
    const limit = self.stack[self.stack_top - 2];
    const current = self.stack[self.stack_top - 3];
    const step_value: i64 = if (step_value_raw.isInt()) step_value_raw.asInt() else try value_runtime.requireInteger(step_value_raw);
    const limit_value: i64 = if (limit.isInt()) limit.asInt() else try value_runtime.requireInteger(limit);
    const current_value: i64 = if (current.isInt()) current.asInt() else try value_runtime.requireInteger(current);
    self.stack[self.stack_top - 3] = Value.fromBool(if (step_value < 0) current_value > limit_value else current_value < limit_value);
    self.stack_top -= 2;
}

pub fn step(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0) return error.InvalidInstruction;
    const encoded_slots: u64 = @intCast(operand);
    const current_slot: usize = @intCast(encoded_slots >> 32);
    const step_slot: usize = @intCast(encoded_slots & 0xffffffff);
    const frame = &self.frames[self.frame_top];
    if (current_slot >= frame.locals.len or step_slot >= frame.locals.len) return error.InvalidLocal;
    const current_value = frame.locals[current_slot];
    const step_value = frame.locals[step_slot];
    const current = if (current_value.isInt()) current_value.asInt() else try value_runtime.requireInteger(current_value);
    const increment = if (step_value.isInt()) step_value.asInt() else try value_runtime.requireInteger(step_value);
    frame.locals[current_slot] = try value_runtime.integer(current +| increment);
}
