const std = @import("std");

pub const min: i64 = -(@as(i64, 1) << 47);
pub const max: i64 = (@as(i64, 1) << 47) - 1;
pub const Operation = enum { add, subtract, multiply, divide, modulo };
pub const Error = error{ IntegerOutOfRange, DivisionByZero };

pub fn validate(value: i64) Error!i64 {
    if (value < min or value > max) return error.IntegerOutOfRange;
    return value;
}

/// All integer execution and folding share the same bounded, truncating rules.
pub fn evaluate(operation: Operation, lhs: i64, rhs: i64) Error!i64 {
    _ = try validate(lhs);
    _ = try validate(rhs);
    const result = switch (operation) {
        .add => std.math.add(i64, lhs, rhs) catch return error.IntegerOutOfRange,
        .subtract => std.math.sub(i64, lhs, rhs) catch return error.IntegerOutOfRange,
        .multiply => std.math.mul(i64, lhs, rhs) catch return error.IntegerOutOfRange,
        .divide => if (rhs == 0) return error.DivisionByZero else @divTrunc(lhs, rhs),
        .modulo => if (rhs == 0) return error.DivisionByZero else @rem(lhs, rhs),
    };
    return validate(result);
}
