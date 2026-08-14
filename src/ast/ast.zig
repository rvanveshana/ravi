const std = @import("std");

pub const ExprId = u32;
pub const StmtId = u32;

pub const Span = struct { first: usize, last: usize, line: usize };

pub const UnaryOp = enum { negate, not };
pub const BinaryOp = enum { add, subtract, multiply, divide, modulo, equal, not_equal, less, less_equal, greater, greater_equal, logic_and, logic_or, in_op, is };
pub const Visibility = enum { public, private, protected, internal };

pub const Expr = struct {
    span: Span,
    kind: Kind,

    pub const Kind = union(enum) {
        integer: i64,
        float: f64,
        string: []const u8,
        formatted_string: struct { template: []const u8, first_arg: usize, arg_count: usize },
        boolean: bool,
        none,
        name: []const u8,
        spawn: ExprId,
        wait: ExprId,
        member: struct { object: ExprId, name: []const u8 },
        unary: struct { op: UnaryOp, operand: ExprId },
        binary: struct { op: BinaryOp, left: ExprId, right: ExprId },
        call: struct { callee: ExprId, first_arg: usize, arg_count: usize, keyword_first: usize = 0, keyword_count: usize = 0 },
        assignment: struct { name: []const u8, value: ExprId, target: ?ExprId = null, annotation: ?[]const u8 = null, array_type: bool = false },
        lambda: struct { params_first: usize, params_count: usize, body: ExprId },
        array: struct { first: usize, count: usize },
        tuple: struct { first: usize, count: usize },
        set: struct { first: usize, count: usize },
        map: struct { first: usize, count: usize },
        index: struct { object: ExprId, index: ExprId },
        slice: struct { object: ExprId, start: ?ExprId, end: ?ExprId },
    };
};

pub const ParameterKind = enum { positional, variadic, keyword_variadic };
pub const Parameter = struct { name: []const u8, annotation: ?[]const u8, span: Span, default_value: ?i64 = null, kind: ParameterKind = .positional };
pub const Decorator = struct { name: []const u8, span: Span };
pub const ParseDiagnostic = struct { message: []const u8, span: Span };

pub const Stmt = struct {
    span: Span,
    kind: Kind,

    pub const Kind = union(enum) {
        expression: ExprId,
        return_stmt: ?ExprId,
        yield_stmt: ?ExprId,
        raise_stmt: ?ExprId,
        import: struct { module: []const u8, names_first: usize, names_count: usize },
        function: struct { name: []const u8, params_first: usize, params_count: usize, return_type: ?[]const u8, body_first: usize, body_count: usize, decorators_first: usize, decorators_count: usize, visibility: Visibility },
        class_decl: struct { name: []const u8, base: ?[]const u8 = null, body_first: usize, body_count: usize, visibility: Visibility },
        control: struct { keyword: []const u8, condition: ?ExprId, body_first: usize, body_count: usize, else_first: usize = 0, else_count: usize = 0, target: ?[]const u8 = null, iterable: ?ExprId = null },
        try_stmt: struct { body_first: usize, body_count: usize, except_first: usize = 0, except_count: usize = 0, except_binding: ?[]const u8 = null, except_match: ?ExprId = null, finally_first: usize = 0, finally_count: usize = 0 },
        context: struct { value: ExprId, binding: ?[]const u8 = null, body_first: usize, body_count: usize },
        transfer: []const u8,
    };
};

pub const Module = struct {
    allocator: std.mem.Allocator,
    expressions: std.ArrayListUnmanaged(Expr) = .empty,
    format_args: std.ArrayListUnmanaged(ExprId) = .empty,
    statements: std.ArrayListUnmanaged(Stmt) = .empty,
    parameters: std.ArrayListUnmanaged(Parameter) = .empty,
    call_args: std.ArrayListUnmanaged(ExprId) = .empty,
    call_keywords: std.ArrayListUnmanaged([]const u8) = .empty,
    import_names: std.ArrayListUnmanaged([]const u8) = .empty,
    import_modules: std.ArrayListUnmanaged([]u8) = .empty,
    decorators: std.ArrayListUnmanaged(Decorator) = .empty,
    docstring: ?[]const u8 = null,
    diagnostics: std.ArrayListUnmanaged(ParseDiagnostic) = .empty,

    pub fn deinit(self: *Module) void {
        self.expressions.deinit(self.allocator);
        self.format_args.deinit(self.allocator);
        self.statements.deinit(self.allocator);
        self.parameters.deinit(self.allocator);
        self.call_args.deinit(self.allocator);
        self.call_keywords.deinit(self.allocator);
        self.import_names.deinit(self.allocator);
        for (self.import_modules.items) |name| self.allocator.free(name);
        self.import_modules.deinit(self.allocator);
        self.decorators.deinit(self.allocator);
        self.diagnostics.deinit(self.allocator);
    }
};
