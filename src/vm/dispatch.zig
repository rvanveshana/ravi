const std = @import("std");
const Value = @import("value.zig").Value;
const bytecode = @import("ravi_bytecode");

pub const ExecutionResult = union(enum) {
    ok: Value,
    runtime_error: []const u8,
};

pub const FastDispatcher = struct {
    pub inline fn dispatchLoop(code: []const bytecode.Instruction, constants: []const Value, registers: []Value) ExecutionResult {
        var pc: usize = 0;
        while (pc < code.len) : (pc += 1) {
            const inst = code[pc];
            switch (inst.op) {
                .constant => {
                    registers[inst.dest] = constants[inst.operand];
                },
                .add => {
                    const lhs = registers[inst.lhs];
                    const rhs = registers[inst.rhs];
                    if (lhs.isInt() and rhs.isInt()) {
                        registers[inst.dest] = Value.fromInt(lhs.asInt() + rhs.asInt());
                    } else if (lhs.isFloat() or rhs.isFloat()) {
                        const lf = if (lhs.isFloat()) lhs.asFloat() else @as(f64, @floatFromInt(lhs.asInt()));
                        const rf = if (rhs.isFloat()) rhs.asFloat() else @as(f64, @floatFromInt(rhs.asInt()));
                        registers[inst.dest] = Value.fromFloat(lf + rf);
                    }
                },
                .return_value => {
                    return .{ .ok = registers[inst.dest] };
                },
                else => {},
            }
        }
        return .{ .ok = Value.nil() };
    }
};
