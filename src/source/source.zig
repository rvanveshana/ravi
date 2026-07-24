const std = @import("std");

pub const SourceId = enum(u32) { _ };

pub const Location = struct {
    line: usize,
    column: usize,
};

pub const Source = struct {
    name: []const u8,
    text: []const u8,
    line_starts: []const usize,
};

/// Owns immutable source buffers and gives every input a stable identity.
/// Files, editor overlays, generated code, and tests can all enter the front
/// end through this interface without giving parser phases filesystem access.
pub const Manager = struct {
    allocator: std.mem.Allocator,
    sources: std.ArrayListUnmanaged(Source) = .empty,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Manager) void {
        for (self.sources.items) |source| {
            self.allocator.free(source.name);
            self.allocator.free(source.text);
            self.allocator.free(source.line_starts);
        }
        self.sources.deinit(self.allocator);
    }

    pub fn add(self: *Manager, name: []const u8, text: []const u8) !SourceId {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);
        var starts: std.ArrayListUnmanaged(usize) = .empty;
        errdefer starts.deinit(self.allocator);
        try starts.append(self.allocator, 0);
        for (text, 0..) |byte, offset| if (byte == '\n' and offset + 1 <= text.len) try starts.append(self.allocator, offset + 1);
        const owned_starts = try starts.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned_starts);
        const id: SourceId = @enumFromInt(@as(u32, @intCast(self.sources.items.len)));
        try self.sources.append(self.allocator, .{ .name = owned_name, .text = owned_text, .line_starts = owned_starts });
        return id;
    }

    pub fn get(self: *const Manager, id: SourceId) ?Source {
        const index: usize = @intFromEnum(id);
        if (index >= self.sources.items.len) return null;
        return self.sources.items[index];
    }

    pub fn location(self: *const Manager, id: SourceId, offset: usize) ?Location {
        const source = self.get(id) orelse return null;
        if (offset > source.text.len) return null;
        var low: usize = 0;
        var high = source.line_starts.len;
        while (low + 1 < high) {
            const middle = low + (high - low) / 2;
            if (source.line_starts[middle] <= offset) low = middle else high = middle;
        }
        return .{ .line = low + 1, .column = offset - source.line_starts[low] + 1 };
    }
};

test "source manager owns buffers and resolves locations" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const id = try manager.add("example.rk", "one\ntwo\n");
    const source = manager.get(id).?;
    try std.testing.expectEqualStrings("example.rk", source.name);
    const location = manager.location(id, 5).?;
    try std.testing.expectEqual(@as(usize, 2), location.line);
    try std.testing.expectEqual(@as(usize, 2), location.column);
}

test "source manager indexes many lines for stable random lookup" {
    var text: std.ArrayListUnmanaged(u8) = .empty;
    defer text.deinit(std.testing.allocator);
    for (0..10_000) |_| try text.appendSlice(std.testing.allocator, "x\n");
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    const id = try manager.add("large.rk", text.items);
    const location = manager.location(id, 19_998).?;
    try std.testing.expectEqual(@as(usize, 10_000), location.line);
    try std.testing.expectEqual(@as(usize, 1), location.column);
}
