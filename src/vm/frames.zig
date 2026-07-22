pub const Frame = struct {
    return_ip: usize,
    base: usize,
    locals: [64]i64 = @splat(0),
    captures: [64]i64 = @splat(0),
    capture_count: usize = 0,
};

pub const Closure = struct {
    function_index: usize,
    captures: [64]i64 = @splat(0),
    capture_count: usize = 0,
};

pub const Cell = struct { value: i64 };
