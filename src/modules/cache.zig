const std = @import("std");

pub const Entry = struct {
    name: []u8,
    fingerprint: u64,
    bytes: []u8,
    dependencies: std.ArrayListUnmanaged([]u8) = .empty,
};

pub const Cache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    max_entries: usize = 1024,

    pub fn init(allocator: std.mem.Allocator, max_entries: usize) Cache {
        return .{ .allocator = allocator, .max_entries = max_entries };
    }
    pub fn deinit(self: *Cache) void {
        for (self.entries.items) |*entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.bytes);
            for (entry.dependencies.items) |dependency| self.allocator.free(dependency);
            entry.dependencies.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }
    pub fn put(self: *Cache, name: []const u8, fingerprint: u64, bytes: []const u8, dependencies: []const []const u8) !void {
        if (self.max_entries == 0) return error.CacheFull;
        if (self.find(name)) |index| self.removeAt(index);
        if (self.entries.items.len >= self.max_entries) self.removeAt(0);
        var entry = Entry{ .name = try self.allocator.dupe(u8, name), .fingerprint = fingerprint, .bytes = try self.allocator.dupe(u8, bytes) };
        errdefer { self.allocator.free(entry.name); self.allocator.free(entry.bytes); }
        for (dependencies) |dependency| try entry.dependencies.append(self.allocator, try self.allocator.dupe(u8, dependency));
        try self.entries.append(self.allocator, entry);
    }
    pub fn get(self: *const Cache, name: []const u8, fingerprint: u64) ?[]const u8 {
        for (self.entries.items) |entry| if (entry.fingerprint == fingerprint and std.mem.eql(u8, entry.name, name)) return entry.bytes;
        return null;
    }
    pub fn invalidate(self: *Cache, changed: []const u8) void {
        var invalidated = std.ArrayListUnmanaged([]const u8).empty;
        defer {
            for (invalidated.items[1..]) |owned_name| self.allocator.free(owned_name);
            invalidated.deinit(self.allocator);
        }
        invalidated.append(self.allocator, changed) catch return;
        var cursor: usize = 0;
        while (cursor < invalidated.items.len) : (cursor += 1) {
            const dependency_name = invalidated.items[cursor];
            var index: usize = 0;
            while (index < self.entries.items.len) {
                const entry = &self.entries.items[index];
                var affected = std.mem.eql(u8, entry.name, dependency_name);
                for (entry.dependencies.items) |dependency| {
                    if (std.mem.eql(u8, dependency, dependency_name)) affected = true;
                }
                if (affected) {
                    const removed_name = self.allocator.dupe(u8, entry.name) catch null;
                    if (removed_name) |owned_name| invalidated.append(self.allocator, owned_name) catch self.allocator.free(owned_name);
                    self.removeAt(index);
                } else index += 1;
            }
        }
    }
    fn find(self: *const Cache, name: []const u8) ?usize { for (self.entries.items, 0..) |entry, i| if (std.mem.eql(u8, entry.name, name)) return i; return null; }
    fn removeAt(self: *Cache, index: usize) void {
        var entry = self.entries.orderedRemove(index);
        self.allocator.free(entry.name); self.allocator.free(entry.bytes);
        for (entry.dependencies.items) |dependency| self.allocator.free(dependency);
        entry.dependencies.deinit(self.allocator);
    }
};

test "artifact cache reuses entries and invalidates dependents" {
    var cache = Cache.init(std.testing.allocator, 4); defer cache.deinit();
    const deps = [_][]const u8{"core"};
    try cache.put("app", 7, "bytecode", &deps);
    try std.testing.expectEqualStrings("bytecode", cache.get("app", 7).?);
    try std.testing.expect(cache.get("app", 8) == null);
    cache.invalidate("core");
    try std.testing.expect(cache.get("app", 7) == null);
}

test "artifact cache invalidation propagates through dependency chains" {
    var cache = Cache.init(std.testing.allocator, 8); defer cache.deinit();
    const core_deps = [_][]const u8{"core"};
    const app_deps = [_][]const u8{"lib"};
    try cache.put("lib", 1, "lib-bytes", &core_deps);
    try cache.put("app", 2, "app-bytes", &app_deps);
    cache.invalidate("core");
    try std.testing.expect(cache.get("lib", 1) == null);
    try std.testing.expect(cache.get("app", 2) == null);
}
