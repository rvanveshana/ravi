const bytecode = @import("ravi_bytecode");
const operators = @import("operators.zig");
const state_helpers = @import("state_helpers.zig");
const value_runtime = @import("value_runtime.zig");

pub fn binary(comptime Error: type, self: anytype, operation: bytecode.OpCode, ip: *usize) Error!void {
    operators.binary(self, operation) catch |err| {
        if (!state_helpers.handleFaultWithError(self, ip, err)) return err;
    };
}

pub fn compare(comptime Error: type, self: anytype, operation: bytecode.OpCode, ip: *usize) Error!void {
    operators.compare(self, operation) catch |err| {
        if (!state_helpers.handleFaultWithError(self, ip, err)) return err;
    };
}

pub fn modulo(comptime Error: type, self: anytype, ip: *usize) Error!bool {
    if (self.stack_top < 2) return error.StackUnderflow;
    const rhs = try value_runtime.requireInteger(self.stack[self.stack_top - 1]);
    if (rhs == 0) {
        if (!state_helpers.handleFaultWithError(self, ip, error.DivisionByZero)) return error.DivisionByZero;
        return true;
    }
    self.stack[self.stack_top - 2] = try value_runtime.integer(@rem(try value_runtime.requireInteger(self.stack[self.stack_top - 2]), rhs));
    self.stack_top -= 1;
    return false;
}
