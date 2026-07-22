pub fn call(self: anytype, chunk: anytype, operand: i64, ip: *usize) !void {
    if (operand < 0 or operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
    if (self.frame_top + 1 >= self.frames.len) return error.CallStackOverflow;
    const function = chunk.functions.items[@intCast(operand)];
    if (self.stack_top < function.arity) return error.StackUnderflow;
    const base = self.stack_top - function.arity;
    self.frame_top += 1;
    self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base };
    for (0..function.arity) |i| self.frames[self.frame_top].locals[i] = self.stack[base + i];
    if (self.trace_count < self.trace.len) {
        self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
        self.trace_count += 1;
    }
    ip.* = function.entry - 1;
}

pub fn callValue(self: anytype, chunk: anytype, arity_operand: i64, ip: *usize) !void {
    if (arity_operand < 0) return error.InvalidFunction;
    const arity: usize = @intCast(arity_operand);
    if (self.stack_top < arity + 1) return error.StackUnderflow;
    const handle = self.stack[self.stack_top - arity - 1];
    const function_index: usize = if (handle <= -4000) {
        const slot: usize = @intCast(-handle - 4000);
        if (slot >= self.closure_count) return error.InvalidFunction;
        const closure = self.closures[slot];
        const function = chunk.functions.items[closure.function_index];
        if (function.arity != arity or self.frame_top + 1 >= self.frames.len) return error.InvalidFunction;
        const base = self.stack_top - arity;
        self.frame_top += 1;
        self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base - 1, .captures = closure.captures, .capture_count = closure.capture_count };
        for (0..arity) |i| self.frames[self.frame_top].locals[i] = self.stack[base + i];
        if (self.trace_count < self.trace.len) {
            self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
            self.trace_count += 1;
        }
        ip.* = function.entry - 1;
        return;
    } else blk: {
        if (handle > -3000) return error.InvalidFunction;
        break :blk @intCast(-handle - 3000);
    };
    if (function_index >= chunk.functions.items.len) return error.InvalidFunction;
    const function = chunk.functions.items[function_index];
    if (function.arity != arity or self.frame_top + 1 >= self.frames.len) return error.InvalidFunction;
    const base = self.stack_top - arity;
    self.frame_top += 1;
    self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base - 1 };
    for (0..arity) |i| self.frames[self.frame_top].locals[i] = self.stack[base + i];
    if (self.trace_count < self.trace.len) {
        self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
        self.trace_count += 1;
    }
    ip.* = function.entry - 1;
}
