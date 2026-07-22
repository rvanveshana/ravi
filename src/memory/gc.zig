const std = @import("std");

pub const Collector = struct {
    arena: std.heap.ArenaAllocator,
    bytes_allocated: usize = 0,
    allocations: usize = 0,
    collections: usize = 0,
    roots: std.ArrayListUnmanaged(*anyopaque) = .empty,
    marked: std.ArrayListUnmanaged(*anyopaque) = .empty,

    pub fn init(backing: std.mem.Allocator) Collector {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }
    pub fn deinit(self: *Collector) void {
        self.roots.deinit(self.arena.child_allocator);
        self.marked.deinit(self.arena.child_allocator);
        self.arena.deinit();
    }
    pub fn allocator(self: *Collector) std.mem.Allocator {
        return self.arena.allocator();
    }
    pub fn create(self: *Collector, comptime T: type) !*T {
        const value = try self.allocator().create(T);
        self.bytes_allocated += @sizeOf(T);
        self.allocations += 1;
        return value;
    }
    /// Registering roots and safepoints now gives the runtime a collector
    /// neutral contract; the arena collector intentionally retains memory
    /// until shutdown so registered objects remain valid.
    pub fn addRoot(self: *Collector, root: *anyopaque) !void {
        try self.roots.append(self.arena.child_allocator, root);
    }
    pub fn removeRoot(self: *Collector, root: *anyopaque) void {
        for (self.roots.items, 0..) |item, i| {
            if (item == root) {
                _ = self.roots.swapRemove(i);
                return;
            }
        }
    }
    pub fn safepoint(self: *Collector) void {
        _ = self;
    }
    pub fn mark(self: *Collector, object: *anyopaque) !void {
        for (self.marked.items) |item| if (item == object) return;
        try self.marked.append(self.arena.child_allocator, object);
    }
    pub fn isMarked(self: *const Collector, object: *anyopaque) bool {
        for (self.marked.items) |item| if (item == object) return true;
        return false;
    }
    pub fn collect(self: *Collector) void {
        self.collections += 1;
        self.marked.clearRetainingCapacity();
        for (self.roots.items) |root| self.mark(root) catch {};
    }
};
