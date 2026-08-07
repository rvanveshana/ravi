const state_helpers = @import("state_helpers.zig");

pub fn begin(comptime Error: type, self: anytype, operand: i64, code_len: usize) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(code_len))) return error.InvalidJump;
    self.handler_ip = @intCast(operand);
    self.handler_stack_top = self.stack_top;
    self.handler_frame_top = self.frame_top;
    self.handler_trace_count = self.trace_count;
    self.handler_active = true;
}

pub fn end(self: anytype) void {
    self.handler_active = false;
}

pub fn raiseValue(comptime Error: type, self: anytype, ip: *usize, code_len: usize) Error!void {
    if (self.stack_top == 0) {
        if (!self.handler_active or self.last_exception.isNil()) return error.RaisedException;
    } else self.last_exception = self.stack[self.stack_top - 1];
    if (!self.handler_active) return error.RaisedException;
    self.handler_active = false;
    self.stack_top = self.handler_stack_top;
    try state_helpers.push(self, self.last_exception);
    state_helpers.unwindFrames(self, self.handler_frame_top);
    self.trace_count = self.handler_trace_count;
    ip.* = if (self.handler_ip == 0) code_len - 1 else self.handler_ip - 1;
}
