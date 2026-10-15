const std = @import("std");

pub const ModuleId = enum(u32) { _ };
pub const Visibility = enum { public, internal, private };
pub const Symbol = struct { name: []const u8, visibility: Visibility };

const Module = struct {
    name: []const u8,
    dependencies: std.ArrayListUnmanaged(ModuleId) = .empty,
    exports: std.ArrayListUnmanaged(Symbol) = .empty,
};
const VisitState = enum { unseen, visiting, done };

pub const ResolveError = std.mem.Allocator.Error || error{ DuplicateModule, UnknownModule, ImportCycle, MissingSymbol, PrivateSymbol };

/// Filesystem-independent module graph and public-interface table. The CLI,
/// editor overlays, package manager, and tests provide canonical module names;
/// semantic analysis consumes stable IDs from this resolver.
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    modules: std.ArrayListUnmanaged(Module) = .empty,

    pub fn init(allocator: std.mem.Allocator) Resolver {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Resolver) void {
        for (self.modules.items) |*module| {
            self.allocator.free(module.name);
            for (module.exports.items) |symbol| self.allocator.free(symbol.name);
            module.dependencies.deinit(self.allocator);
            module.exports.deinit(self.allocator);
        }
        self.modules.deinit(self.allocator);
    }

    pub fn register(self: *Resolver, name: []const u8) ResolveError!ModuleId {
        if (self.find(name) != null) return error.DuplicateModule;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        const id: ModuleId = @enumFromInt(@as(u32, @intCast(self.modules.items.len)));
        try self.modules.append(self.allocator, .{ .name = owned });
        return id;
    }

    pub fn find(self: *const Resolver, name: []const u8) ?ModuleId {
        for (self.modules.items, 0..) |module, module_index| if (std.mem.eql(u8, module.name, name)) return @enumFromInt(@as(u32, @intCast(module_index)));
        return null;
    }

    pub fn addDependency(self: *Resolver, from: ModuleId, to: ModuleId) ResolveError!void {
        const from_index = try self.index(from);
        _ = try self.index(to);
        for (self.modules.items[from_index].dependencies.items) |existing| if (existing == to) return;
        try self.modules.items[from_index].dependencies.append(self.allocator, to);
        errdefer _ = self.modules.items[from_index].dependencies.pop();
        if (try self.hasCycle()) return error.ImportCycle;
    }

    pub fn exportSymbol(self: *Resolver, module: ModuleId, name: []const u8, visibility: Visibility) ResolveError!void {
        const module_index = try self.index(module);
        for (self.modules.items[module_index].exports.items) |symbol| if (std.mem.eql(u8, symbol.name, name)) return error.DuplicateModule;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.modules.items[module_index].exports.append(self.allocator, .{ .name = owned, .visibility = visibility });
    }

    pub fn bindImport(self: *const Resolver, module: ModuleId, name: []const u8) ResolveError!Symbol {
        const module_index = try self.index(module);
        for (self.modules.items[module_index].exports.items) |symbol| {
            if (!std.mem.eql(u8, symbol.name, name)) continue;
            if (symbol.visibility != .public) return error.PrivateSymbol;
            return symbol;
        }
        return error.MissingSymbol;
    }

    pub fn moduleExports(self: *const Resolver, module: ModuleId) []const Symbol {
        const module_index = @intFromEnum(module);
        if (module_index >= self.modules.items.len) return &.{};
        return self.modules.items[module_index].exports.items;
    }

    /// Returns the canonical name used in diagnostics and cache keys.
    pub fn moduleName(self: *const Resolver, module: ModuleId) ResolveError![]const u8 {
        return self.modules.items[try self.index(module)].name;
    }

    pub fn topologicalOrder(self: *const Resolver, allocator: std.mem.Allocator) ResolveError![]ModuleId {
        const states = try allocator.alloc(VisitState, self.modules.items.len);
        defer allocator.free(states);
        @memset(states, .unseen);
        var result: std.ArrayListUnmanaged(ModuleId) = .empty;
        errdefer result.deinit(allocator);
        for (self.modules.items, 0..) |_, index_value| try self.visit(@enumFromInt(@as(u32, @intCast(index_value))), states, &result, allocator);
        return result.toOwnedSlice(allocator);
    }

    /// Returns the changed module followed by every transitive importer. This
    /// is the minimal recompilation set for interface or source changes.
    pub fn invalidationSet(self: *const Resolver, changed: ModuleId, allocator: std.mem.Allocator) ResolveError![]ModuleId {
        _ = try self.index(changed);
        const visited = try allocator.alloc(bool, self.modules.items.len);
        defer allocator.free(visited);
        @memset(visited, false);
        var result: std.ArrayListUnmanaged(ModuleId) = .empty;
        errdefer result.deinit(allocator);
        try result.append(allocator, changed);
        visited[@intFromEnum(changed)] = true;
        var cursor: usize = 0;
        while (cursor < result.items.len) : (cursor += 1) {
            const dependency = result.items[cursor];
            for (self.modules.items, 0..) |module, module_index| {
                if (visited[module_index]) continue;
                for (module.dependencies.items) |candidate| {
                    if (candidate != dependency) continue;
                    visited[module_index] = true;
                    try result.append(allocator, @enumFromInt(@as(u32, @intCast(module_index))));
                    break;
                }
            }
        }
        return result.toOwnedSlice(allocator);
    }

    fn visit(self: *const Resolver, module: ModuleId, states: []VisitState, result: *std.ArrayListUnmanaged(ModuleId), allocator: std.mem.Allocator) ResolveError!void {
        const module_index = try self.index(module);
        switch (states[module_index]) {
            .done => return,
            .visiting => return error.ImportCycle,
            .unseen => states[module_index] = .visiting,
        }
        for (self.modules.items[module_index].dependencies.items) |dependency| try self.visit(dependency, states, result, allocator);
        states[module_index] = .done;
        try result.append(allocator, module);
    }

    fn index(self: *const Resolver, module: ModuleId) ResolveError!usize {
        const value: usize = @intFromEnum(module);
        if (value >= self.modules.items.len) return error.UnknownModule;
        return value;
    }

    fn hasCycle(self: *const Resolver) ResolveError!bool {
        const order = self.topologicalOrder(self.allocator) catch |err| return if (err == error.ImportCycle) true else err;
        self.allocator.free(order);
        return false;
    }
};

test "resolver orders dependencies and binds only public exports" {
    var resolver = Resolver.init(std.testing.allocator);
    defer resolver.deinit();
    const app = try resolver.register("app");
    const math = try resolver.register("math");
    try resolver.addDependency(app, math);
    try resolver.exportSymbol(math, "add", .public);
    try resolver.exportSymbol(math, "secret", .private);
    try std.testing.expectEqualStrings("add", (try resolver.bindImport(math, "add")).name);
    try std.testing.expectError(error.PrivateSymbol, resolver.bindImport(math, "secret"));
    const order = try resolver.topologicalOrder(std.testing.allocator);
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(math, order[0]);
    try std.testing.expectEqual(app, order[1]);
}

test "resolver rejects import cycles" {
    var resolver = Resolver.init(std.testing.allocator);
    defer resolver.deinit();
    const first = try resolver.register("first");
    const second = try resolver.register("second");
    try resolver.addDependency(first, second);
    try std.testing.expectError(error.ImportCycle, resolver.addDependency(second, first));
}

test "resolver computes selective transitive invalidation" {
    var resolver = Resolver.init(std.testing.allocator);
    defer resolver.deinit();
    const app = try resolver.register("app");
    const service = try resolver.register("service");
    const math = try resolver.register("math");
    _ = try resolver.register("unrelated");
    try resolver.addDependency(app, service);
    try resolver.addDependency(service, math);
    const invalidated = try resolver.invalidationSet(math, std.testing.allocator);
    defer std.testing.allocator.free(invalidated);
    try std.testing.expectEqual(@as(usize, 3), invalidated.len);
    try std.testing.expectEqual(math, invalidated[0]);
    try std.testing.expectEqual(service, invalidated[1]);
    try std.testing.expectEqual(app, invalidated[2]);
    try std.testing.expectEqualStrings("math", try resolver.moduleName(math));
}
