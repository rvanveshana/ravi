const state_helpers = @import("state_helpers.zig");
const value_runtime = @import("value_runtime.zig");
const Value = @import("ravi_vm_value").Value;

pub fn duplicate(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    try state_helpers.push(self, self.stack[self.stack_top - 1]);
}

pub fn discard(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    self.stack_top -= 1;
}

pub fn guardFloat(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0 or !self.stack[self.stack_top - 1].isFloat()) return error.TypeGuardFailed;
}

pub fn guardInteger(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0 or !self.stack[self.stack_top - 1].isInt()) return error.TypeGuardFailed;
}

pub fn guardBoolean(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.TypeGuardFailed;
    const value = self.stack[self.stack_top - 1];
    if (!value.isBool() and (!value.isInt() or (value.asInt() != 0 and value.asInt() != 1))) return error.TypeGuardFailed;
}

pub fn guardString(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0 or self.stack[self.stack_top - 1].handleKind() != .string) return error.TypeGuardFailed;
}

pub fn negate(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    self.stack[self.stack_top - 1] = if (value.isFloat()) Value.fromFloat(-value.asFloat()) else try value_runtime.integer(-(try value_runtime.requireInteger(value)));
}

pub fn logicalNot(comptime Error: type, self: anytype) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    self.stack[self.stack_top - 1] = Value.fromBool(!self.stack[self.stack_top - 1].truthy());
}
