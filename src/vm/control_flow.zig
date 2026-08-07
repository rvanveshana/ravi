const state_helpers = @import("state_helpers.zig");
const Value = @import("ravi_vm_value").Value;

pub fn jumpIfFalse(comptime Error: type, self: anytype, operand: i64, ip: *usize, code_len: usize) Error!void {
    if (self.stack_top == 0) return error.StackUnderflow;
    const value = self.stack[self.stack_top - 1];
    self.stack_top -= 1;
    if (!value.truthy()) try setTarget(operand, ip, code_len);
}

pub fn jump(comptime Error: type, operand: i64, ip: *usize, code_len: usize) Error!void {
    try setTarget(operand, ip, code_len);
}

fn setTarget(operand: i64, ip: *usize, code_len: usize) error{InvalidJump}!void {
    if (operand < 0 or operand >= @as(i64, @intCast(code_len))) return error.InvalidJump;
    const target: usize = @intCast(operand);
    ip.* = if (target == 0) code_len - 1 else target - 1;
}

pub fn returnValue(comptime Error: type, self: anytype, ip: *usize) Error!?Value {
    const value = if (self.stack_top == 0) Value.nil() else self.stack[self.stack_top - 1];
    if (self.frame_top == 0) return value;
    const old_base = self.frames[self.frame_top].base;
    const return_ip = self.frames[self.frame_top].return_ip;
    self.frames[self.frame_top].deinit(self.allocator);
    self.frame_top -= 1;
    if (self.trace_count > 0) self.trace_count -= 1;
    self.stack_top = old_base;
    try state_helpers.push(self, value);
    ip.* = return_ip;
    return null;
}
