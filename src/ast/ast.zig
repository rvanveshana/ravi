const std = @import("std");

pub const ExprId = u32;
pub const StmtId = u32;

pub const Span = struct { first: usize, last: usize, line: usize };

pub const UnaryOp = enum { negate, not };
pub const BinaryOp = enum { add, subtract, multiply, divide, equal, not_equal, less, less_equal, greater, greater_equal, logic_and, logic_or, in_op, is };
pub const Visibility = enum { public, private, protected, internal };

pub const Expr = struct {
    span: Span,
    kind: Kind,

    pub const Kind = union(enum) {
        integer: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
        none,
        name: []const u8,
        unary: struct { op: UnaryOp, operand: ExprId },
        binary: struct { op: BinaryOp, left: ExprId, right: ExprId },
        call: struct { callee: ExprId, first_arg: usize, arg_count: usize },
        assignment: struct { name: []const u8, value: ExprId, annotation: ?[]const u8 = null, array_type: bool = false },
        lambda: struct { params_first: usize, params_count: usize, body: ExprId },
        array: struct { first: usize, count: usize },
        tuple: struct { first: usize, count: usize },
        set: struct { first: usize, count: usize },
        map: struct { first: usize, count: usize },
        index: struct { object: ExprId, index: ExprId },
        slice: struct { object: ExprId, start: ?ExprId, end: ?ExprId },
    };
};

pub const Parameter = struct { name: []const u8, annotation: ?[]const u8, span: Span };
pub const Decorator = struct { name: []const u8, span: Span };
pub const ParseDiagnostic = struct { message: []const u8, span: Span };

pub const Stmt = struct {
    span: Span,
    kind: Kind,

    pub const Kind = union(enum) {
        expression: ExprId,
        return_stmt: ?ExprId,
        import: struct { module: []const u8, names_first: usize, names_count: usize },
        function: struct { name: []const u8, params_first: usize, params_count: usize, return_type: ?[]const u8, body_first: usize, body_count: usize, decorators_first: usize, decorators_count: usize, visibility: Visibility },
        class_decl: struct { name: []const u8, base: ?[]const u8 = null, body_first: usize, body_count: usize, visibility: Visibility },
        control: struct { keyword: []const u8, condition: ?ExprId, body_first: usize, body_count: usize },
        context: struct { value: ExprId, body_first: usize, body_count: usize },
        transfer: []const u8,
    };
};

pub const Module = struct {
    allocator: std.mem.Allocator,
    expressions: std.ArrayListUnmanaged(Expr) = .empty,
    statements: std.ArrayListUnmanaged(Stmt) = .empty,
    parameters: std.ArrayListUnmanaged(Parameter) = .empty,
    import_names: std.ArrayListUnmanaged([]const u8) = .empty,
    decorators: std.ArrayListUnmanaged(Decorator) = .empty,
    docstring: ?[]const u8 = null,
    diagnostics: std.ArrayListUnmanaged(ParseDiagnostic) = .empty,

    pub fn deinit(self: *Module) void {
        self.expressions.deinit(self.allocator);
        self.statements.deinit(self.allocator);
        self.parameters.deinit(self.allocator);
        self.import_names.deinit(self.allocator);
        self.decorators.deinit(self.allocator);
        self.diagnostics.deinit(self.allocator);
    }
};
