const std = @import("std");
const lexer = @import("ravi_lexer");
const types = @import("ravi_types");
const ast = @import("ravi_ast");
const config = @import("ravi_config");
const symbols = @import("ravi_semantic_symbols");

pub const SemanticError = std.mem.Allocator.Error || error{ DuplicateDeclaration, MissingFunctionType, UnknownVisibilityTarget, UnknownType, UnknownBaseClass, TypeMismatch };
pub const Visibility = symbols.Visibility;
pub const Symbol = symbols.Symbol;
pub const Scope = symbols.Scope;
pub const Reference = symbols.Reference;
pub const Boundary = struct { expression: ast.ExprId, from: types.Type, to: types.Type, guard: types.Guard };

pub const Analyzer = struct {
    allocator: std.mem.Allocator,
    declarations: std.ArrayListUnmanaged([]const u8) = .empty,
    symbols: symbols.Graph,
    boundaries: std.ArrayListUnmanaged(Boundary) = .empty,
    last_token: ?lexer.Token = null,

    pub fn init(allocator: std.mem.Allocator) Analyzer {
        return .{ .allocator = allocator, .symbols = symbols.Graph.init(allocator) };
    }
    pub fn deinit(self: *Analyzer) void {
        self.declarations.deinit(self.allocator);
        self.symbols.deinit();
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
        for (module.statements.items, 0..) |statement, statement_index| switch (statement.kind) {
            .function => |function| {
                if (isClassMethod(module, statement_index)) continue;
                try self.declare(root, function.name, types.fromName(function.return_type orelse "dinamika"), .internal);
                const child = try self.pushScope(root);
                const end = function.params_first + function.params_count;
                for (module.parameters.items[function.params_first..end]) |parameter| try self.declare(child, parameter.name, types.fromName(parameter.annotation orelse "dinamika"), .private);
            },
            .class_decl => |class_decl| {
                if (class_decl.base) |base| {
                    var found = false;
                    for (self.symbols.scopes.items[@intFromEnum(root)].symbols.items) |symbol| {
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

    fn isClassMethod(module: *const ast.Module, statement_index: usize) bool {
        for (module.statements.items) |statement| switch (statement.kind) {
            .class_decl => |class_decl| if (statement_index >= class_decl.body_first and statement_index < class_decl.body_first + class_decl.body_count) return true,
            else => {},
        };
        return false;
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

    fn pushScope(self: *Analyzer, parent: ?symbols.ScopeId) !symbols.ScopeId {
        return self.symbols.pushScope(parent);
    }
    fn declare(self: *Analyzer, scope_id: symbols.ScopeId, name: []const u8, ty: types.Type, visibility: Visibility) SemanticError!void {
        _ = self.symbols.declare(scope_id, name, ty, visibility) catch |err| switch (err) {
            error.DuplicateDeclaration => return error.DuplicateDeclaration,
            error.InvalidScope => return error.UnknownType,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }
    pub fn recordBoundary(self: *Analyzer, expression: ast.ExprId, from: types.Type, to: types.Type) !void {
        if (!types.assignable(from, to)) return error.UnknownType;
        try self.boundaries.append(self.allocator, .{ .expression = expression, .from = from, .to = to, .guard = types.guardFor(from, to) });
    }
    pub fn resolve(self: *const Analyzer, scope_id: symbols.ScopeId, name: []const u8) ?Symbol {
        return self.symbols.resolve(scope_id, name);
    }

    pub fn reference(self: *Analyzer, scope_id: symbols.ScopeId, name: []const u8) !symbols.SymbolId {
        return self.symbols.reference(scope_id, name);
    }

    pub fn capture(self: *Analyzer, scope_id: symbols.ScopeId, name: []const u8) !void {
        const symbol = self.resolve(scope_id, name) orelse return error.UnknownType;
        try self.symbols.capture(scope_id, symbol.id);
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
