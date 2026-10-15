const std = @import("std");
const ast = @import("ravi_ast");
const types = @import("ravi_types");
const symbols = @import("ravi_semantic_symbols");
const Error = @import("analyzer.zig").SemanticError;
const dynamic = types.Type{ .kind = .dynamic, .name = "dynamic" };

pub fn analyze(analyzer: anytype, module: *const ast.Module) Error!void {
    var context = Context(@TypeOf(analyzer)){ .analyzer = analyzer, .module = module };
    defer context.functions.deinit(analyzer.allocator);
    const root = try analyzer.symbols.pushScope(null);
    try context.suite(root, 0, module.statements.items.len, null);
}

fn Context(comptime Analyzer: type) type {
    return struct {
        analyzer: Analyzer,
        module: *const ast.Module,
        functions: std.ArrayListUnmanaged(struct { symbol: symbols.SymbolId, statement: usize }) = .empty,
        const Self = @This();

        fn declare(self: *Self, scope: symbols.ScopeId, name: []const u8, ty: types.Type) Error!symbols.SymbolId {
            return self.analyzer.symbols.declare(scope, name, ty, .internal);
        }

        fn annotation(self: *Self, name: ?[]const u8) Error!types.Type {
            _ = self;
            const ty = types.fromName(name orelse "dynamic");
            if (!types.isValid(ty)) return error.UnknownType;
            return ty;
        }

        fn bindVariable(self: *Self, scope: symbols.ScopeId, name: []const u8, ty: types.Type) Error!void {
            for (self.analyzer.symbols.scopes.items[@intFromEnum(scope)].symbols.items) |symbol| if (std.mem.eql(u8, symbol.name, name)) return;
            _ = try self.declare(scope, name, ty);
        }

        fn suite(self: *Self, scope: symbols.ScopeId, first: usize, count: usize, return_type: ?types.Type) Error!void {
            if (first > self.module.statements.items.len or count > self.module.statements.items.len - first) return error.InvalidScope;
            const end = first + count;
            // Register declarations in their lexical scope, skipping nested suites.
            var index = first;
            while (index < end) {
                const statement = self.module.statements.items[index];
                self.analyzer.last_span = statement.span;
                switch (statement.kind) {
                    .function => |function| {
                        const symbol = try self.declare(scope, function.name, .{ .kind = .function, .name = "function" });
                        try self.functions.append(self.analyzer.allocator, .{ .symbol = symbol, .statement = index });
                    },
                    .class_decl => |class| {
                        _ = try self.declare(scope, class.name, dynamic);
                    },
                    else => {},
                }
                index = next(statement, index);
            }
            index = first;
            while (index < end) {
                const statement = self.module.statements.items[index];
                self.analyzer.last_span = statement.span;
                switch (statement.kind) {
                    .expression => |id| {
                        _ = try self.expression(scope, id);
                    },
                    .function => |function| {
                        const child = try self.analyzer.symbols.pushScope(scope);
                        if (function.method_name != null or isMethod(self.module, index)) try self.bindVariable(child, "tanna", dynamic);
                        for (self.module.parameters.items[function.params_first .. function.params_first + function.params_count]) |parameter| {
                            self.analyzer.last_span = parameter.span;
                            _ = try self.declare(child, parameter.name, try self.annotation(parameter.annotation));
                        }
                        const expected = try self.annotation(function.return_type);
                        try self.suite(child, function.body_first, function.body_count, expected);
                    },
                    .class_decl => |class| {
                        if (class.base) |base| if (self.analyzer.symbols.resolve(scope, base) == null and !std.mem.eql(u8, base, "Exception") and !std.mem.eql(u8, base, "BaseException")) return error.UnknownBaseClass;
                        const child = try self.analyzer.symbols.pushScope(scope);
                        try self.suite(child, class.body_first, class.body_count, null);
                    },
                    .return_stmt => |value| {
                        const actual = if (value) |id| try self.expression(scope, id) else types.fromName("none");
                        if (return_type) |expected| if (!types.assignable(actual, expected)) return error.TypeMismatch;
                    },
                    .yield_stmt, .raise_stmt => |value| {
                        if (value) |id| _ = try self.expression(scope, id);
                    },
                    .control => |control| {
                        if (control.condition) |id| _ = try self.expression(scope, id);
                        if (control.iterable) |id| _ = try self.expression(scope, id);
                        if (control.target) |target| try self.bindVariable(scope, target, dynamic);
                        try self.suite(scope, control.body_first, control.body_count, return_type);
                        try self.suite(scope, control.else_first, control.else_count, return_type);
                    },
                    .try_stmt => |value| {
                        try self.suite(scope, value.body_first, value.body_count, return_type);
                        if (value.except_binding) |binding| try self.bindVariable(scope, binding, dynamic);
                        if (value.except_match) |id| _ = try self.expression(scope, id);
                        try self.suite(scope, value.except_first, value.except_count, return_type);
                        try self.suite(scope, value.finally_first, value.finally_count, return_type);
                    },
                    .context => |value| {
                        _ = try self.expression(scope, value.value);
                        if (value.binding) |binding| try self.bindVariable(scope, binding, dynamic);
                    },
                    .import => {}, // Resolved and removed by the module linker before lowering.
                    .transfer => {},
                }
                index = next(statement, index);
            }
        }

        fn expression(self: *Self, scope: symbols.ScopeId, id: ast.ExprId) Error!types.Type {
            if (id >= self.module.expressions.items.len) return error.InvalidName;
            const expr = self.module.expressions.items[id];
            self.analyzer.last_span = expr.span;
            return switch (expr.kind) {
                .integer => types.fromName("int"),
                .float => types.fromName("float"),
                .string => types.fromName("str"),
                .boolean => types.fromName("bool"),
                .none => types.fromName("none"),
                .name => |name| blk: {
                    if (self.analyzer.symbols.resolve(scope, name)) |symbol| {
                        _ = try self.analyzer.symbols.reference(scope, name);
                        break :blk symbol.type;
                    }
                    if (builtin(name)) break :blk dynamic;
                    return error.InvalidName;
                },
                .assignment => |value| blk: {
                    const actual = try self.expression(scope, value.value);
                    const expected = try self.annotation(value.annotation);
                    if (value.array_type) {
                        try self.analyzer.validateTypedArray(self.module, value.value, value.annotation orelse "dynamic");
                    } else if (!types.assignable(actual, expected)) return error.TypeMismatch;
                    if (value.target) |target| {
                        _ = try self.expression(scope, target);
                    } else {
                        const ty = if (value.array_type) dynamic else if (value.annotation != null) expected else actual;
                        try self.bindVariable(scope, value.name, ty);
                    }
                    break :blk actual;
                },
                .unary => |value| blk: {
                    const ty = try self.expression(scope, value.operand);
                    break :blk if (value.op == .not) types.fromName("bool") else ty;
                },
                .binary => |value| blk: {
                    const lhs = try self.expression(scope, value.left);
                    const rhs = try self.expression(scope, value.right);
                    break :blk switch (value.op) {
                        .add, .subtract, .multiply, .divide, .modulo => types.join(lhs, rhs),
                        else => types.fromName("bool"),
                    };
                },
                .call => |call| blk: {
                    _ = try self.expression(scope, call.callee);
                    var declaration: ?usize = null;
                    const callee = self.module.expressions.items[call.callee];
                    if (callee.kind == .name) if (self.analyzer.symbols.resolve(scope, callee.kind.name)) |symbol| {
                        for (self.functions.items) |function| if (function.symbol == symbol.id) {
                            declaration = function.statement;
                            break;
                        };
                    };
                    for (self.module.call_args.items[call.first_arg .. call.first_arg + call.arg_count], 0..) |argument, arg_index| {
                        const actual = try self.expression(scope, argument);
                        if (declaration) |statement_id| {
                            const function = self.module.statements.items[statement_id].kind.function;
                            if (arg_index < function.params_count) {
                                const parameter = self.module.parameters.items[function.params_first + arg_index];
                                if (parameter.kind == .positional and !types.assignable(actual, try self.annotation(parameter.annotation))) return error.TypeMismatch;
                            }
                        }
                    }
                    break :blk if (declaration) |statement_id| try self.annotation(self.module.statements.items[statement_id].kind.function.return_type) else dynamic;
                },
                .member => |value| blk: {
                    _ = try self.expression(scope, value.object);
                    break :blk dynamic;
                },
                .index => |value| blk: {
                    _ = try self.expression(scope, value.object);
                    _ = try self.expression(scope, value.index);
                    break :blk dynamic;
                },
                .slice => |value| blk: {
                    _ = try self.expression(scope, value.object);
                    if (value.start) |start| _ = try self.expression(scope, start);
                    if (value.end) |end| _ = try self.expression(scope, end);
                    break :blk dynamic;
                },
                inline .array, .tuple, .set, .map => |value| blk: {
                    for (self.module.collection_items.items[value.first .. value.first + value.count]) |element| _ = try self.expression(scope, element);
                    break :blk dynamic;
                },
                .formatted_string => |value| blk: {
                    for (self.module.format_args.items[value.first_arg .. value.first_arg + value.arg_count]) |argument| _ = try self.expression(scope, argument);
                    break :blk types.fromName("str");
                },
                .spawn, .wait => |value| blk: {
                    _ = try self.expression(scope, value);
                    break :blk dynamic;
                },
                .lambda => |value| blk: {
                    const child = try self.analyzer.symbols.pushScope(scope);
                    for (self.module.parameters.items[value.params_first .. value.params_first + value.params_count]) |parameter| _ = try self.declare(child, parameter.name, try self.annotation(parameter.annotation));
                    _ = try self.expression(child, value.body);
                    break :blk types.fromName("function");
                },
            };
        }
    };
}

fn next(statement: ast.Stmt, index: usize) usize {
    return switch (statement.kind) {
        .function => |v| @max(index + 1, v.body_first + v.body_count),
        .class_decl => |v| @max(index + 1, v.body_first + v.body_count),
        .control => |v| @max(index + 1, @max(v.body_first + v.body_count, if (v.else_count == 0) 0 else v.else_first + v.else_count)),
        .try_stmt => |v| @max(index + 1, @max(v.body_first + v.body_count, @max(if (v.except_count == 0) 0 else v.except_first + v.except_count, if (v.finally_count == 0) 0 else v.finally_first + v.finally_count))),
        else => index + 1,
    };
}

fn isMethod(module: *const ast.Module, index: usize) bool {
    for (module.statements.items) |statement| if (statement.kind == .class_decl) {
        const class = statement.kind.class_decl;
        if (index >= class.body_first and index < class.body_first + class.body_count) return true;
    };
    return false;
}

fn builtin(name: []const u8) bool {
    const names = [_][]const u8{ "print", "mudrisu", "type", "vidha", "sleep", "malagu", "range", "shreni", "add", "sub", "mul", "div", "mod", "__ravi_exception", "guru", "super" };
    for (names) |known| if (std.mem.eql(u8, name, known)) return true;
    return false;
}
