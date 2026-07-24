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
