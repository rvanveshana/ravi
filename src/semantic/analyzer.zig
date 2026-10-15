const std = @import("std");
const types = @import("ravi_types");
const ast = @import("ravi_ast");
const symbols = @import("ravi_semantic_symbols");

pub const SemanticError = std.mem.Allocator.Error || error{ DuplicateDeclaration, MissingFunctionType, UnknownVisibilityTarget, UnknownType, UnknownBaseClass, TypeMismatch, InvalidName, InvalidFunction, InvalidScope, UnknownSymbol };
pub const Visibility = symbols.Visibility;
pub const Symbol = symbols.Symbol;
pub const Scope = symbols.Scope;
pub const Reference = symbols.Reference;
pub const Boundary = struct { expression: ast.ExprId, from: types.Type, to: types.Type, guard: types.Guard };

pub const Analyzer = struct {
    allocator: std.mem.Allocator,
    symbols: symbols.Graph,
    boundaries: std.ArrayListUnmanaged(Boundary) = .empty,
    last_span: ?ast.Span = null,

    pub fn init(allocator: std.mem.Allocator) Analyzer {
        return .{ .allocator = allocator, .symbols = symbols.Graph.init(allocator) };
    }
    pub fn deinit(self: *Analyzer) void {
        self.symbols.deinit();
        self.boundaries.deinit(self.allocator);
    }

    pub fn analyzeModule(self: *Analyzer, module: *const ast.Module) SemanticError!void {
        return @import("scope_analysis.zig").analyze(self, module);
    }

    pub fn validateTypedArray(self: *Analyzer, module: *const ast.Module, expression_id: ast.ExprId, element_name: []const u8) SemanticError!void {
        _ = self;
        const expression = module.expressions.items[expression_id];
        const array = switch (expression.kind) {
            .array => |value| value,
            else => return error.TypeMismatch,
        };
        const expected = types.fromName(element_name);
        if (!types.isValid(expected)) return error.UnknownType;
        for (module.collection_items.items[array.first .. array.first + array.count]) |element_id| {
            const element = module.expressions.items[element_id];
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
};
