const bytecode = @import("ravi_bytecode");
const Value = @import("ravi_vm_value").Value;

pub const ExecutionResult = union(enum) {
    ok: Value,
    runtime_error: []const u8,
};

/// Small, allocation-free dispatcher used to validate the NaN-boxed execution
/// contract. The main VM will adopt this representation after all opcodes have
/// equivalent handlers and differential tests.
pub const FastDispatcher = struct {
    pub fn supports(code: []const bytecode.Instruction) bool {
        for (code) |instruction| switch (instruction.op) {
            .constant, .add, .return_value, .halt => {},
            else => return false,
        };
        return code.len != 0;
    }

    pub fn dispatchLoop(code: []const bytecode.Instruction, stack: []Value) ExecutionResult {
        var pc: usize = 0;
        var top: usize = 0;
        while (pc < code.len) : (pc += 1) {
            const instruction = code[pc];
            switch (instruction.op) {
                .constant => {
                    if (top >= stack.len) return .{ .runtime_error = "stack overflow" };
                    stack[top] = Value.fromInt(instruction.operand);
                    top += 1;
                },
                .add => {
                    if (top < 2) return .{ .runtime_error = "stack underflow" };
                    const right = stack[top - 1];
                    const left = stack[top - 2];
                    if (!left.isInt() or !right.isInt()) return .{ .runtime_error = "type error" };
                    stack[top - 2] = Value.fromInt(left.asInt() + right.asInt());
                    top -= 1;
                },
                .return_value, .halt => {
                    return .{ .ok = if (top == 0) Value.nil() else stack[top - 1] };
                },
                else => return .{ .runtime_error = "unsupported opcode" },
            }
        }
        return .{ .ok = if (top == 0) Value.nil() else stack[top - 1] };
    }
};

test "fast dispatcher executes its supported bytecode contract" {
    const std = @import("std");
    const code = [_]bytecode.Instruction{
        .{ .op = .constant, .operand = 20 },
        .{ .op = .constant, .operand = 22 },
        .{ .op = .add },
        .{ .op = .return_value },
    };
    var stack: [8]Value = undefined;
    const result = FastDispatcher.dispatchLoop(&code, &stack);
    switch (result) {
        .ok => |value| try std.testing.expectEqual(@as(i64, 42), value.asInt()),
        .runtime_error => return error.UnexpectedRuntimeError,
    }
}
