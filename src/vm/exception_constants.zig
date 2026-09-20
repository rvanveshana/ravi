const std = @import("std");

pub const ExceptionInfo = struct {
    code: i64,
    name: []const u8,
    message: []const u8,
};

pub const base_exception = ExceptionInfo{ .code = 100, .name = "BaseException", .message = "base exception" };
pub const exception = ExceptionInfo{ .code = 101, .name = "Exception", .message = "exception" };
pub const runtime_error = ExceptionInfo{ .code = 500, .name = "RuntimeError", .message = "runtime error" };
pub const arithmetic_error = ExceptionInfo{ .code = 510, .name = "ArithmeticError", .message = "arithmetic error" };
pub const zero_division_error = ExceptionInfo{ .code = 511, .name = "ZeroDivisionError", .message = "division by zero; check the divisor before dividing" };
pub const overflow_error = ExceptionInfo{ .code = 512, .name = "OverflowError", .message = "numeric result is too large" };
pub const lookup_error = ExceptionInfo{ .code = 520, .name = "LookupError", .message = "lookup failed" };
pub const index_error = ExceptionInfo{ .code = 521, .name = "IndexError", .message = "index is outside the collection bounds" };
pub const key_error = ExceptionInfo{ .code = 522, .name = "KeyError", .message = "dictionary key was not found" };
pub const name_error = ExceptionInfo{ .code = 532, .name = "NameError", .message = "name is not defined" };
pub const unbound_local_error = ExceptionInfo{ .code = 533, .name = "UnboundLocalError", .message = "local name was used before it was bound" };
pub const attribute_error = ExceptionInfo{ .code = 534, .name = "AttributeError", .message = "attribute is not available" };
pub const invalid_function_error = ExceptionInfo{ .code = 540, .name = "InvalidFunctionError", .message = "value is not a valid function" };
pub const invalid_instruction_error = ExceptionInfo{ .code = 541, .name = "InvalidInstructionError", .message = "the VM rejected invalid or corrupted bytecode" };
pub const stack_error = ExceptionInfo{ .code = 550, .name = "StackError", .message = "stack operation failed" };
pub const stack_underflow_error = ExceptionInfo{ .code = 551, .name = "StackUnderflowError", .message = "stack underflow" };
pub const stack_overflow_error = ExceptionInfo{ .code = 552, .name = "StackOverflowError", .message = "stack overflow" };
pub const call_stack_overflow_error = ExceptionInfo{ .code = 553, .name = "CallStackOverflowError", .message = "call stack overflow" };
pub const invalid_local_error = ExceptionInfo{ .code = 554, .name = "InvalidLocalError", .message = "local variable access is invalid" };
pub const invalid_jump_error = ExceptionInfo{ .code = 555, .name = "InvalidJumpError", .message = "jump target is invalid" };
pub const collection_error = ExceptionInfo{ .code = 560, .name = "CollectionError", .message = "collection operation failed" };
pub const collection_full_error = ExceptionInfo{ .code = 561, .name = "CollectionFullError", .message = "collection is full" };
pub const string_too_long_error = ExceptionInfo{ .code = 570, .name = "StringTooLongError", .message = "string exceeds the supported length" };
pub const memory_error = ExceptionInfo{ .code = 580, .name = "MemoryError", .message = "memory operation failed" };
pub const out_of_memory_error = ExceptionInfo{ .code = 581, .name = "OutOfMemoryError", .message = "out of memory" };
pub const debugger_paused_error = ExceptionInfo{ .code = 590, .name = "DebuggerPausedError", .message = "execution is paused by the debugger" };
pub const raised_exception_error = ExceptionInfo{ .code = 599, .name = "RaisedExceptionError", .message = "a raised value escaped without a matching handler" };
pub const value_error = ExceptionInfo{ .code = 400, .name = "ValueError", .message = "value is invalid" };
pub const type_error = ExceptionInfo{ .code = 401, .name = "TypeError", .message = "value has the wrong type for this operation" };
pub const validation_error = ExceptionInfo{ .code = 402, .name = "ValidationError", .message = "validation failed" };

pub fn fromCode(code: i64) ?ExceptionInfo {
    inline for (.{
        base_exception,        exception,              runtime_error,             arithmetic_error,          zero_division_error,
        overflow_error,        lookup_error,           index_error,               key_error,                 name_error,
        unbound_local_error,   attribute_error,        invalid_function_error,    invalid_instruction_error, stack_error,
        stack_underflow_error, stack_overflow_error,   call_stack_overflow_error, invalid_local_error,       invalid_jump_error,
        collection_error,      collection_full_error,  string_too_long_error,     memory_error,              out_of_memory_error,
        debugger_paused_error, raised_exception_error, value_error,               type_error,                validation_error,
    }) |info| {
        if (info.code == code) return info;
    }
    return null;
}

pub fn fromName(name: []const u8) ?ExceptionInfo {
    inline for (.{
        base_exception,        exception,              runtime_error,             arithmetic_error,          zero_division_error,
        overflow_error,        lookup_error,           index_error,               key_error,                 name_error,
        unbound_local_error,   attribute_error,        invalid_function_error,    invalid_instruction_error, stack_error,
        stack_underflow_error, stack_overflow_error,   call_stack_overflow_error, invalid_local_error,       invalid_jump_error,
        collection_error,      collection_full_error,  string_too_long_error,     memory_error,              out_of_memory_error,
        debugger_paused_error, raised_exception_error, value_error,               type_error,                validation_error,
    }) |info| {
        if (std.mem.eql(u8, info.name, name)) return info;
    }
    return null;
}

pub fn fromRuntimeError(err: anyerror) ?ExceptionInfo {
    return switch (err) {
        error.OutOfMemory => out_of_memory_error,
        error.StackOverflow => stack_overflow_error,
        error.StackUnderflow => stack_underflow_error,
        error.DivisionByZero => zero_division_error,
        error.InvalidInstruction => invalid_instruction_error,
        error.InvalidLocal => invalid_local_error,
        error.InvalidJump => invalid_jump_error,
        error.CallStackOverflow => call_stack_overflow_error,
        error.InvalidFunction => invalid_function_error,
        error.TypeGuardFailed => type_error,
        error.CollectionFull => collection_full_error,
        error.InvalidIndex => index_error,
        error.MissingKey => key_error,
        error.StringTooLong => string_too_long_error,
        error.RaisedException => raised_exception_error,
        error.IntegerOutOfRange => overflow_error,
        error.DebuggerPaused => debugger_paused_error,
        else => null,
    };
}

pub fn messageFor(err: anyerror) []const u8 {
    return if (fromRuntimeError(err)) |info| info.message else @errorName(err);
}

test "runtime errors use the configured exception identity" {
    const info = fromRuntimeError(error.DivisionByZero).?;
    try std.testing.expectEqual(zero_division_error.code, info.code);
    try std.testing.expectEqualStrings("ZeroDivisionError", info.name);
}
