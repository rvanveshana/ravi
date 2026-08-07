const bytecode = @import("ravi_bytecode");
const Value = @import("ravi_vm_value").Value;

pub fn call(self: anytype, chunk: anytype, operand: i64, ip: *usize) !void {
    if (operand < 0 or operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
    if (self.frame_top + 1 >= self.frames.len) return error.CallStackOverflow;
    const function = chunk.functions.items[@intCast(operand)];
    if (self.stack_top < function.arity) return error.StackUnderflow;
    const base = self.stack_top - function.arity;
    self.frame_top += 1;
    self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base };
    try self.frames[self.frame_top].ensureLocals(self.allocator, function.arity);
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
    const function_index: usize = if (handle.handleKind() == .closure) {
        const slot = handle.handleIndex().?;
        if (slot >= self.closure_count) return error.InvalidFunction;
        const closure = self.closures[slot];
        const function = chunk.functions.items[closure.function_index];
        if (arity > function.arity or self.frame_top + 1 >= self.frames.len) return error.InvalidFunction;
        const base = self.stack_top - arity;
        self.frame_top += 1;
        self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base - 1, .captures = closure.captures };
        try self.frames[self.frame_top].ensureLocals(self.allocator, function.arity);
        for (0..function.arity) |i| self.frames[self.frame_top].locals[i] = if (i < arity) self.stack[base + i] else if (function.defaults[i]) |default| Value.fromInt(default) else Value.nil();
        if (self.trace_count < self.trace.len) {
            self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
            self.trace_count += 1;
        }
        ip.* = function.entry - 1;
        return;
    } else blk: {
        if (handle.handleKind() != .function) return error.InvalidFunction;
        break :blk handle.handleIndex().?;
    };
    if (function_index >= chunk.functions.items.len) return error.InvalidFunction;
    const function = chunk.functions.items[function_index];
    if (arity > function.arity or self.frame_top + 1 >= self.frames.len) return error.InvalidFunction;
    const base = self.stack_top - arity;
    self.frame_top += 1;
    self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base - 1 };
    try self.frames[self.frame_top].ensureLocals(self.allocator, function.arity);
    for (0..function.arity) |i| self.frames[self.frame_top].locals[i] = if (i < arity) self.stack[base + i] else if (function.defaults[i]) |default| Value.fromInt(default) else Value.nil();
    if (self.trace_count < self.trace.len) {
        self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
        self.trace_count += 1;
    }
    ip.* = function.entry - 1;
}

pub fn callMethod(self: anytype, chunk: anytype, operand: i64, ip: *usize) !void {
    if (operand < 0 or operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
    if (self.frame_top + 1 >= self.frames.len) return error.CallStackOverflow;
    var function = chunk.functions.items[@intCast(operand)];
    if (self.stack_top < function.arity + 1) return error.StackUnderflow;
    const base = self.stack_top - function.arity - 1;
    const receiver = self.stack[base];
    if (receiver.handleKind() != .instance) return error.InvalidFunction;
    const instance_slot = receiver.handleIndex() orelse return error.InvalidFunction;
    if (instance_slot >= self.instance_count) return error.InvalidFunction;
    const class_index = self.instances[instance_slot].class_index;
    if (bytecode.lookupMethod(chunk.classes.items, chunk.methods.items, class_index, function.name)) |resolved| {
        if (resolved >= chunk.functions.items.len) return error.InvalidFunction;
        var declaring_class: ?usize = null;
        var method_visibility: u8 = 0;
        for (chunk.methods.items) |method| if (method.function_index == resolved) {
            declaring_class = method.class_index;
            method_visibility = method.visibility;
            break;
        };
        if (method_visibility == 2 and !bytecode.canAccessProtected(chunk.classes.items, declaring_class orelse return error.InvalidFunction, self.frames[self.frame_top].owner_class)) return error.InvalidFunction;
        function = chunk.functions.items[resolved];
    }
    self.frame_top += 1;
    self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = base, .owner_class = class_index };
    try self.frames[self.frame_top].ensureLocals(self.allocator, function.arity + 1);
    self.frames[self.frame_top].locals[0] = receiver;
    for (0..function.arity) |index| self.frames[self.frame_top].locals[index + 1] = self.stack[base + index + 1];
    if (self.trace_count < self.trace.len) {
        self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
        self.trace_count += 1;
    }
    ip.* = function.entry - 1;
}

pub fn callSuper(self: anytype, chunk: anytype, operand: i64, ip: *usize) !void {
    if (operand < 0 or operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidFunction;
    if (self.frame_top + 1 >= self.frames.len) return error.CallStackOverflow;
    const receiver = self.stack[self.stack_top - chunk.functions.items[@intCast(operand)].arity - 1];
    const instance_slot = receiver.handleIndex() orelse return error.InvalidFunction;
    if (receiver.handleKind() != .instance or instance_slot >= self.instance_count) return error.InvalidFunction;
    const owner = self.frames[self.frame_top].owner_class orelse return error.InvalidFunction;
    const base = chunk.classes.items[owner].base orelse return error.InvalidFunction;
    const requested = chunk.functions.items[@intCast(operand)];
    const resolved = bytecode.lookupMethod(chunk.classes.items, chunk.methods.items, base, requested.name) orelse return error.InvalidFunction;
    const function = chunk.functions.items[resolved];
    const call_base = self.stack_top - function.arity - 1;
    self.frame_top += 1;
    self.frames[self.frame_top] = .{ .return_ip = ip.*, .base = call_base, .owner_class = base };
    try self.frames[self.frame_top].ensureLocals(self.allocator, function.arity + 1);
    self.frames[self.frame_top].locals[0] = receiver;
    for (0..function.arity) |index| self.frames[self.frame_top].locals[index + 1] = self.stack[call_base + index + 1];
    if (self.trace_count < self.trace.len) {
        self.trace[self.trace_count] = .{ .function = function.name, .instruction = function.entry };
        self.trace_count += 1;
    }
    ip.* = function.entry - 1;
}
