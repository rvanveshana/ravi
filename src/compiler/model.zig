const lexer = @import("ravi_lexer");
pub const Visibility = enum(u8) { public, private, protected, internal };

pub const FunctionDecl = struct {
    name: []const u8,
    params_first: usize,
    params_count: usize,
    fixed_count: usize,
    varargs_index: ?usize = null,
    kwargs_index: ?usize = null,
    param_names: [64][]const u8 = undefined,
    param_types: [64]?[]const u8 = @splat(null),
    defaults: [64]?i64 = @splat(null),
    captures: [64][]const u8 = undefined,
    capture_count: usize = 0,
    body_first: usize,
    body_end: usize,
    anonymous: bool = false,
    method: bool = false,
    visibility: Visibility = .public,
    resumable: bool = false,
    suspension_count: usize = 0,
};

pub const LoopContext = struct {
    continue_target: usize,
    breaks_first: usize,
    continues_first: usize,
};

pub const RangeParts = struct {
    args: [3][]const lexer.Token,
    count: usize,
};
