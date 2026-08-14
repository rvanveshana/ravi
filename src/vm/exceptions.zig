const std = @import("std");
const state_helpers = @import("state_helpers.zig");

pub fn matchType(self: anytype, chunk: anytype) !void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const expected = self.stack[self.stack_top - 1];
    const raised = self.stack[self.stack_top - 2];
    var matched = false;
    if (expected.handleKind() == .exception and raised.handleKind() == .exception) {
        const expected_slot = expected.handleIndex() orelse return error.InvalidInstruction;
        const raised_slot = raised.handleIndex() orelse return error.InvalidInstruction;
        if (expected_slot >= self.exception_count or raised_slot >= self.exception_count) return error.InvalidInstruction;
        const expected_name = self.exceptions[expected_slot].name;
        const raised_name = self.exceptions[raised_slot].name;
        matched = std.mem.eql(u8, raised_name, expected_name);
        if (std.mem.eql(u8, expected_name, "BaseException")) matched = isBuiltinException(raised_name);
        if (std.mem.eql(u8, expected_name, "Exception")) matched = isBuiltinException(raised_name) and !std.mem.eql(u8, raised_name, "BaseException");
        if (std.mem.eql(u8, expected_name, "ArithmeticError")) matched = std.mem.eql(u8, raised_name, "ZeroDivisionError") or std.mem.eql(u8, raised_name, "OverflowError") or std.mem.eql(u8, raised_name, "ArithmeticError");
        if (std.mem.eql(u8, expected_name, "LookupError")) matched = std.mem.eql(u8, raised_name, "IndexError") or std.mem.eql(u8, raised_name, "KeyError") or std.mem.eql(u8, raised_name, "LookupError");
    } else if (raised.handleKind() == .exception) {
        const expected_name = self.stringSlice(expected) orelse return error.TypeGuardFailed;
        const slot = raised.handleIndex() orelse return error.InvalidInstruction;
        if (slot >= self.exception_count) return error.InvalidInstruction;
        const raised_name = self.exceptions[slot].name;
        matched = std.mem.eql(u8, raised_name, expected_name);
        if (std.mem.eql(u8, expected_name, "BaseException")) matched = isBuiltinException(raised_name);
        if (std.mem.eql(u8, expected_name, "Exception")) matched = isBuiltinException(raised_name) and !std.mem.eql(u8, raised_name, "BaseException");
        if (std.mem.eql(u8, expected_name, "ArithmeticError")) matched = std.mem.eql(u8, raised_name, "ZeroDivisionError") or std.mem.eql(u8, raised_name, "OverflowError") or std.mem.eql(u8, raised_name, "ArithmeticError");
        if (std.mem.eql(u8, expected_name, "LookupError")) matched = std.mem.eql(u8, raised_name, "IndexError") or std.mem.eql(u8, raised_name, "KeyError") or std.mem.eql(u8, raised_name, "LookupError");
    } else if (self.stringSlice(raised)) |raised_name| {
        const expected_name = self.stringSlice(expected) orelse return error.TypeGuardFailed;
        matched = std.mem.eql(u8, raised_name, expected_name);
        if (std.mem.eql(u8, expected_name, "BaseException")) matched = isBuiltinException(raised_name);
        if (std.mem.eql(u8, expected_name, "Exception")) matched = isBuiltinException(raised_name) and !std.mem.eql(u8, raised_name, "BaseException");
        if (std.mem.eql(u8, expected_name, "ArithmeticError")) matched = std.mem.eql(u8, raised_name, "ZeroDivisionError") or std.mem.eql(u8, raised_name, "OverflowError") or std.mem.eql(u8, raised_name, "ArithmeticError");
        if (std.mem.eql(u8, expected_name, "LookupError")) matched = std.mem.eql(u8, raised_name, "IndexError") or std.mem.eql(u8, raised_name, "KeyError") or std.mem.eql(u8, raised_name, "LookupError");
    } else if (raised.handleKind() == .instance) {
        const expected_name = self.stringSlice(expected) orelse return error.TypeGuardFailed;
        const slot = raised.handleIndex() orelse return error.InvalidInstruction;
        if (slot >= self.instance_count) return error.InvalidInstruction;
        var class_index = self.instances[slot].class_index;
        var steps: usize = 0;
        while (class_index < chunk.classes.items.len and steps <= chunk.classes.items.len) : (steps += 1) {
            const class_info = chunk.classes.items[class_index];
            if (std.mem.eql(u8, class_info.name, expected_name)) matched = true;
            if ((std.mem.eql(u8, expected_name, "Exception") or std.mem.eql(u8, expected_name, "BaseException")) and class_info.is_exception) matched = true;
            class_index = class_info.base orelse break;
        }
    }
    self.stack[self.stack_top - 2] = @import("ravi_vm_value").Value.fromBool(matched);
    self.stack_top -= 1;
}

fn isBuiltinException(name: []const u8) bool {
    const names = [_][]const u8{
        "BaseException",        "Exception",               "RuntimeError",         "ArithmeticError",     "ZeroDivisionError",  "OverflowError",
        "LookupError",          "IndexError",              "KeyError",             "NameError",           "UnboundLocalError",  "AttributeError",
        "InvalidFunctionError", "InvalidInstructionError", "StackError",           "StackUnderflowError", "StackOverflowError", "CallStackOverflowError",
        "InvalidLocalError",    "InvalidJumpError",        "CollectionError",      "CollectionFullError", "StringTooLongError", "MemoryError",
        "OutOfMemoryError",     "DebuggerPausedError",     "RaisedExceptionError", "ValueError",          "TypeError",          "ValidationError",
    };
    for (names) |candidate| if (std.mem.eql(u8, name, candidate)) return true;
    return false;
}

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
    } else {
        self.last_exception = self.stack[self.stack_top - 1];
        if (self.stringSlice(self.last_exception)) |message| {
            const slot = @import("object_storage.zig").newException(self, message) catch return error.OutOfMemory;
            self.last_exception = @import("ravi_vm_value").Value.fromHandle(.exception, slot) catch return error.InvalidInstruction;
        }
    }
    if (!self.handler_active) return error.RaisedException;
    self.handler_active = false;
    self.stack_top = self.handler_stack_top;
    try state_helpers.push(self, self.last_exception);
    state_helpers.unwindFrames(self, self.handler_frame_top);
    self.trace_count = self.handler_trace_count;
    ip.* = if (self.handler_ip == 0) code_len - 1 else self.handler_ip - 1;
}
