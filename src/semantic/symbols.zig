const std = @import("std");
const types = @import("ravi_types");

pub const SymbolId = enum(u32) { _ };
pub const ScopeId = enum(u32) { _ };

pub const Symbol = struct {
    id: SymbolId,
    name: []const u8,
    type: types.Type,
    visibility: Visibility,
    scope: ScopeId,
};
pub const Reference = struct { scope: ScopeId, name: []const u8, symbol: SymbolId };

pub const Visibility = enum { public, private, protected, internal };

pub const Scope = struct {
    id: ScopeId,
    parent: ?ScopeId,
    symbols: std.ArrayListUnmanaged(Symbol) = .empty,
    captures: std.ArrayListUnmanaged(SymbolId) = .empty,

    pub fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
        self.symbols.deinit(allocator);
        self.captures.deinit(allocator);
    }
};

pub const Graph = struct {
    allocator: std.mem.Allocator,
    scopes: std.ArrayListUnmanaged(Scope) = .empty,
    references: std.ArrayListUnmanaged(Reference) = .empty,
    next_symbol: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) Graph {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Graph) void {
        for (self.scopes.items) |*scope| scope.deinit(self.allocator);
        self.scopes.deinit(self.allocator);
        self.references.deinit(self.allocator);
    }

    pub fn pushScope(self: *Graph, parent: ?ScopeId) !ScopeId {
        const id: ScopeId = @enumFromInt(self.scopes.items.len);
        try self.scopes.append(self.allocator, .{ .id = id, .parent = parent });
        return id;
    }

    pub fn declare(self: *Graph, scope_id: ScopeId, name: []const u8, ty: types.Type, visibility: Visibility) !SymbolId {
        const scope_index = @intFromEnum(scope_id);
        if (scope_index >= self.scopes.items.len) return error.InvalidScope;
        for (self.scopes.items[scope_index].symbols.items) |symbol| {
            if (std.mem.eql(u8, symbol.name, name)) return error.DuplicateDeclaration;
        }
        const id: SymbolId = @enumFromInt(self.next_symbol);
        self.next_symbol += 1;
        try self.scopes.items[scope_index].symbols.append(self.allocator, .{ .id = id, .name = name, .type = ty, .visibility = visibility, .scope = scope_id });
        return id;
    }

    pub fn resolve(self: *const Graph, scope_id: ScopeId, name: []const u8) ?Symbol {
        var current: ?ScopeId = scope_id;
        while (current) |id| {
            const index = @intFromEnum(id);
            if (index >= self.scopes.items.len) return null;
            for (self.scopes.items[index].symbols.items) |symbol| {
                if (std.mem.eql(u8, symbol.name, name)) return symbol;
            }
            current = self.scopes.items[index].parent;
        }
        return null;
    }

    pub fn lookup(self: *const Graph, symbol_id: SymbolId) ?Symbol {
        for (self.scopes.items) |scope| for (scope.symbols.items) |symbol| if (symbol.id == symbol_id) return symbol;
        return null;
    }

    pub fn reference(self: *Graph, scope_id: ScopeId, name: []const u8) !SymbolId {
        const symbol = self.resolve(scope_id, name) orelse return error.UnknownSymbol;
        try self.references.append(self.allocator, .{ .scope = scope_id, .name = name, .symbol = symbol.id });
        return symbol.id;
    }

    pub fn capture(self: *Graph, scope_id: ScopeId, symbol_id: SymbolId) !void {
        const index = @intFromEnum(scope_id);
        if (index >= self.scopes.items.len) return error.InvalidScope;
        const symbol = self.lookup(symbol_id) orelse return error.InvalidSymbol;
        var parent = self.scopes.items[index].parent;
        var visible = false;
        while (parent) |parent_id| {
            if (parent_id == symbol.scope) {
                visible = true;
                break;
            }
            parent = self.scopes.items[@intFromEnum(parent_id)].parent;
        }
        if (!visible) return error.InvalidCapture;
        for (self.scopes.items[index].captures.items) |existing| if (existing == symbol_id) return;
        try self.scopes.items[index].captures.append(self.allocator, symbol_id);
    }
};

test "symbol graph assigns stable ids and resolves lexical shadowing" {
    var graph = Graph.init(std.testing.allocator);
    defer graph.deinit();
    const root = try graph.pushScope(null);
    const outer = try graph.declare(root, "value", types.fromName("int"), .internal);
    const child = try graph.pushScope(root);
    const inner = try graph.declare(child, "value", types.fromName("float"), .private);
    try std.testing.expect(@intFromEnum(inner) != @intFromEnum(outer));
    try std.testing.expectEqual(types.Kind.float, (graph.resolve(child, "value") orelse return error.TestExpectedEqual).type.kind);
    try std.testing.expectEqual(outer, graph.resolve(root, "value").?.id);
    try graph.capture(child, outer);
    try graph.capture(child, outer);
    try std.testing.expectEqual(@as(usize, 1), graph.scopes.items[@intFromEnum(child)].captures.items.len);
    try std.testing.expectEqual(outer, graph.lookup(outer).?.id);
    try std.testing.expectError(error.InvalidCapture, graph.capture(child, inner));
    try std.testing.expectEqual(outer, try graph.reference(child, "value"));
    try std.testing.expectEqual(@as(usize, 1), graph.references.items.len);
}
