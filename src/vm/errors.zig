pub const RuntimeError = error{
    OutOfMemory,
    StackOverflow,
    StackUnderflow,
    DivisionByZero,
    InvalidInstruction,
    InvalidLocal,
    InvalidJump,
    CallStackOverflow,
    InvalidFunction,
    TypeGuardFailed,
    CollectionFull,
    InvalidIndex,
    MissingKey,
    StringTooLong,
    RaisedException,
    IntegerOutOfRange,
    DebuggerPaused,
};

pub const TypeId = enum(i64) {
    integer = 1,
    collection = 2,
    dictionary = 3,
    string = 4,
    function = 5,
    instance = 6,
};

pub fn publicExceptionName(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.OutOfMemory => "OutOfMemoryError",
        error.StackOverflow => "StackOverflowError",
        error.StackUnderflow => "StackUnderflowError",
        error.DivisionByZero => "ZeroDivisionError",
        error.InvalidInstruction => "InvalidInstructionError",
        error.InvalidLocal => "InvalidLocalError",
        error.InvalidJump => "InvalidJumpError",
        error.CallStackOverflow => "CallStackOverflowError",
        error.InvalidFunction => "InvalidFunctionError",
        error.TypeGuardFailed => "TypeError",
        error.CollectionFull => "CollectionFullError",
        error.InvalidIndex => "IndexError",
        error.MissingKey => "KeyError",
        error.StringTooLong => "StringTooLongError",
        error.RaisedException => "RaisedExceptionError",
        error.IntegerOutOfRange => "OverflowError",
        error.DebuggerPaused => "DebuggerPausedError",
        else => null,
    };
}
