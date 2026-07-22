pub const RuntimeError = error{
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
};

pub const TypeId = enum(i64) {
    integer = 1,
    collection = 2,
    dictionary = 3,
    string = 4,
    function = 5,
};
