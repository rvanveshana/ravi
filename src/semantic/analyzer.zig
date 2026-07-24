const std = @import("std");
const lexer = @import("ravi_lexer");
const types = @import("ravi_types");
const ast = @import("ravi_ast");
const config = @import("ravi_config");

pub const SemanticError = std.mem.Allocator.Error || error{ DuplicateDeclaration, MissingFunctionType, UnknownVisibilityTarget, UnknownType, UnknownBaseClass, TypeMismatch };
pub const Visibility = enum { public, private, protected, internal };
pub const Symbol = struct { name: []const u8, type: types.Type, visibility: Visibility, scope_depth: usize };
pub const Scope = struct { parent: ?usize, symbols: std.ArrayListUnmanaged(Symbol) = .empty, captures: std.ArrayListUnmanaged([]const u8) = .empty };
pub const Boundary = struct { expression: ast.ExprId, from: types.Type, to: types.Type, guard: types.Guard };

pub const Analyzer = struct {
    allocator: std.mem.Allocator,
    declarations: std.ArrayListUnmanaged([]const u8) = .empty,
    scopes: std.ArrayListUnmanaged(Scope) = .empty,
    boundaries: std.ArrayListUnmanaged(Boundary) = .empty,
    last_token: ?lexer.Token = null,

    pub fn init(allocator: std.mem.Allocator) Analyzer {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Analyzer) void {
        self.declarations.deinit(self.allocator);
        for (self.scopes.items) |*scope| {
            scope.symbols.deinit(self.allocator);
            scope.captures.deinit(self.allocator);
        }
        self.scopes.deinit(self.allocator);
        self.boundaries.deinit(self.allocator);
    }

    pub fn analyzeModule(self: *Analyzer, module: *const ast.Module) SemanticError!void {
        const root = try self.pushScope(null);
        // Register all class names before validating bases so declaration order
        // does not change the meaning of a hierarchy.
        for (module.statements.items) |statement| switch (statement.kind) {
            .class_decl => |class_decl| try self.declare(root, class_decl.name, types.fromName("kriya"), .internal),
            else => {},
        };
        for (module.statements.items) |statement| switch (statement.kind) {
            .function => |function| {
                try self.declare(root, function.name, types.fromName(function.return_type orelse "dinamika"), .internal);
                const child = try self.pushScope(root);
                const end = function.params_first + function.params_count;
                for (module.parameters.items[function.params_first..end]) |parameter| try self.declare(child, parameter.name, types.fromName(parameter.annotation orelse "dinamika"), .private);
            },
            .class_decl => |class_decl| {
                if (class_decl.base) |base| {
                    var found = false;
                    for (self.scopes.items[root].symbols.items) |symbol| {
                        if (std.mem.eql(u8, symbol.name, base)) found = true;
                    }
                    if (!found) return error.UnknownBaseClass;
                }
                var method_names: std.ArrayListUnmanaged([]const u8) = .empty;
                defer method_names.deinit(self.allocator);
                const end = @min(class_decl.body_first + class_decl.body_count, module.statements.items.len);
                for (module.statements.items[class_decl.body_first..end]) |member| switch (member.kind) {
                    .function => |function| {
                        for (method_names.items) |existing| if (std.mem.eql(u8, existing, function.name)) return error.DuplicateDeclaration;
                        try method_names.append(self.allocator, function.name);
                    },
                    else => {},
                };
            },
            .expression => |expression_id| {
                switch (module.expressions.items[expression_id].kind) {
                    .assignment => |assignment| if (assignment.array_type) try self.validateTypedArray(module, assignment.value, assignment.annotation orelse "dinamika"),
                    else => {},
                }
            },
            else => {},
        };
    }

    fn validateTypedArray(self: *Analyzer, module: *const ast.Module, expression_id: ast.ExprId, element_name: []const u8) SemanticError!void {
        _ = self;
        const expression = module.expressions.items[expression_id];
        const array = switch (expression.kind) {
            .array => |value| value,
            else => return error.TypeMismatch,
        };
        const expected = types.fromName(element_name);
        if (!types.isValid(expected)) return error.UnknownType;
        for (module.expressions.items[array.first .. array.first + array.count]) |element| {
            const actual: types.Type = switch (element.kind) {
                .integer => .{ .kind = .integer, .name = "int" },
                .float => .{ .kind = .float, .name = "float" },
                .boolean => .{ .kind = .boolean, .name = "bool" },
                .string => .{ .kind = .string, .name = "str" },
                else => .{ .kind = .unknown, .name = "unknown" },
            };
            if (!types.consistent(actual, expected)) return error.TypeMismatch;
        }
    }

    fn pushScope(self: *Analyzer, parent: ?usize) !usize {
        const id = self.scopes.items.len;
        try self.scopes.append(self.allocator, .{ .parent = parent });
        return id;
    }
    fn declare(self: *Analyzer, scope_id: usize, name: []const u8, ty: types.Type, visibility: Visibility) SemanticError!void {
        for (self.scopes.items[scope_id].symbols.items) |symbol| if (std.mem.eql(u8, symbol.name, name)) return error.DuplicateDeclaration;
        try self.scopes.items[scope_id].symbols.append(self.allocator, .{ .name = name, .type = ty, .visibility = visibility, .scope_depth = scope_id });
    }
    pub fn recordBoundary(self: *Analyzer, expression: ast.ExprId, from: types.Type, to: types.Type) !void {
        if (!types.consistent(from, to)) return error.UnknownType;
        try self.boundaries.append(self.allocator, .{ .expression = expression, .from = from, .to = to, .guard = types.guardFor(from, to) });
    }
    pub fn capture(self: *Analyzer, scope_id: usize, name: []const u8) !void {
        if (scope_id >= self.scopes.items.len) return error.UnknownType;
        for (self.scopes.items[scope_id].captures.items) |existing| if (std.mem.eql(u8, existing, name)) return;
        try self.scopes.items[scope_id].captures.append(self.allocator, name);
    }

    pub fn analyze(self: *Analyzer, tokens: []const lexer.Token) SemanticError!void {
        return self.analyzeWithLanguage(tokens, .kn);
    }

    pub fn analyzeWithLanguage(self: *Analyzer, tokens: []const lexer.Token, language: config.SourceLanguage) SemanticError!void {
        var index: usize = 0;
        while (index < tokens.len) : (index += 1) {
            self.last_token = tokens[index];
            const canonical = config.keywordCanonicalFor(language, tokens[index].lexeme) orelse tokens[index].lexeme;
            if (!std.mem.eql(u8, canonical, "function")) continue;
            index += 1;
            if (index >= tokens.len or tokens[index].kind != .identifier) continue;
            const name = tokens[index].lexeme;
            self.last_token = tokens[index];
            for (self.declarations.items) |existing| if (std.mem.eql(u8, existing, name)) return error.DuplicateDeclaration;
            try self.declarations.append(self.allocator, name);
            while (index < tokens.len and tokens[index].kind != .newline) : (index += 1) {
                if (tokens[index].kind != .colon) continue;
                if (index + 1 < tokens.len and tokens[index + 1].kind == .identifier and !types.isValid(types.fromName(tokens[index + 1].lexeme))) {
                    self.last_token = tokens[index + 1];
                    return error.UnknownType;
                }
            }
        }
    }
};
