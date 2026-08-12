const std = @import("std");
const bytecode = @import("ravi_bytecode");
const Value = @import("ravi_vm_value").Value;
const values = @import("value_runtime.zig");
const state = @import("state_helpers.zig");
const errors = @import("errors.zig");

pub fn binary(self: anytype, op: bytecode.OpCode) errors.RuntimeError!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const rhs = self.stack[self.stack_top - 1];
    const lhs = self.stack[self.stack_top - 2];
    if (op == .add and lhs.handleKind() == .string and rhs.handleKind() == .string) {
        const left_slot = lhs.handleIndex().?;
        const right_slot = rhs.handleIndex().?;
        if (left_slot >= self.strings.items.len or right_slot >= self.strings.items.len) return error.InvalidInstruction;
        const left = self.strings.items[left_slot].bytes;
        const right = self.strings.items[right_slot].bytes;
        const combined = try self.allocator.alloc(u8, left.len + right.len);
        defer self.allocator.free(combined);
        @memcpy(combined[0..left.len], left);
        @memcpy(combined[left.len..], right);
        self.stack[self.stack_top - 2] = try state.internString(self, combined);
        self.stack_top -= 1;
        return;
    }
    if ((lhs.isFloat() or lhs.isInt()) and (rhs.isFloat() or rhs.isInt()) and (lhs.isFloat() or rhs.isFloat())) {
        const left = if (lhs.isFloat()) lhs.asFloat() else @as(f64, @floatFromInt(lhs.asInt()));
        const right = if (rhs.isFloat()) rhs.asFloat() else @as(f64, @floatFromInt(rhs.asInt()));
        if (op == .divide and right == 0.0) return error.DivisionByZero;
        self.stack[self.stack_top - 2] = Value.fromFloat(switch (op) {
            .add => left + right,
            .subtract => left - right,
            .multiply => left * right,
            .divide => left / right,
            else => return error.InvalidInstruction,
        });
        self.stack_top -= 1;
        return;
    }
    const left = try values.requireInteger(lhs);
    const right = try values.requireInteger(rhs);
    const result = switch (op) {
        .add => std.math.add(i64, left, right) catch return error.IntegerOutOfRange,
        .subtract => std.math.sub(i64, left, right) catch return error.IntegerOutOfRange,
        .multiply => std.math.mul(i64, left, right) catch return error.IntegerOutOfRange,
        .divide => if (right == 0) return error.DivisionByZero else std.math.divTrunc(i64, left, right) catch return error.IntegerOutOfRange,
        else => return error.InvalidInstruction,
    };
    self.stack[self.stack_top - 2] = try values.integer(result);
    self.stack_top -= 1;
}

pub fn compare(self: anytype, op: bytecode.OpCode) errors.RuntimeError!void {
    if (self.stack_top < 2) return error.StackUnderflow;
    const rhs = self.stack[self.stack_top - 1];
    const lhs = self.stack[self.stack_top - 2];
    if ((op == .equal or op == .not_equal) and lhs.handleKind() == .string and rhs.handleKind() == .string) {
        const left_slot = lhs.handleIndex().?;
        const right_slot = rhs.handleIndex().?;
        if (left_slot >= self.strings.items.len or right_slot >= self.strings.items.len) return error.InvalidInstruction;
        const same = std.mem.eql(u8, self.strings.items[left_slot].bytes, self.strings.items[right_slot].bytes);
        self.stack[self.stack_top - 2] = Value.fromBool(if (op == .equal) same else !same);
        self.stack_top -= 1;
        return;
    }
    if ((lhs.isFloat() or lhs.isInt()) and (rhs.isFloat() or rhs.isInt()) and (lhs.isFloat() or rhs.isFloat())) {
        const left = if (lhs.isFloat()) lhs.asFloat() else @as(f64, @floatFromInt(lhs.asInt()));
        const right = if (rhs.isFloat()) rhs.asFloat() else @as(f64, @floatFromInt(rhs.asInt()));
        self.stack[self.stack_top - 2] = switch (op) {
            .equal => Value.fromBool(left == right),
            .not_equal => Value.fromBool(left != right),
            .less => Value.fromBool(left < right),
            .less_equal => Value.fromBool(left <= right),
            .greater => Value.fromBool(left > right),
            .greater_equal => Value.fromBool(left >= right),
            .logic_and => Value.fromBool(lhs.truthy() and rhs.truthy()),
            .logic_or => Value.fromBool(lhs.truthy() or rhs.truthy()),
            else => return error.InvalidInstruction,
        };
        self.stack_top -= 1;
        return;
    }
    self.stack[self.stack_top - 2] = switch (op) {
        .equal => Value.fromBool(Value.eql(lhs, rhs)),
        .not_equal => Value.fromBool(!Value.eql(lhs, rhs)),
        .less => Value.fromBool((try values.requireInteger(lhs)) < (try values.requireInteger(rhs))),
        .less_equal => Value.fromBool((try values.requireInteger(lhs)) <= (try values.requireInteger(rhs))),
        .greater => Value.fromBool((try values.requireInteger(lhs)) > (try values.requireInteger(rhs))),
        .greater_equal => Value.fromBool((try values.requireInteger(lhs)) >= (try values.requireInteger(rhs))),
        .logic_and => Value.fromBool(lhs.truthy() and rhs.truthy()),
        .logic_or => Value.fromBool(lhs.truthy() or rhs.truthy()),
        else => return error.InvalidInstruction,
    };
    self.stack_top -= 1;
}
