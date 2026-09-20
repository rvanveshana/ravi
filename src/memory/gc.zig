const std = @import("std");

pub const Collector = struct {
    pub const Options = struct { collection_threshold: usize = 1024, stress: bool = false };
    pub const Statistics = struct { bytes: usize, allocations: usize, live: usize, collections: usize };
    const TraceFn = *const fn (*Collector, *anyopaque) anyerror!void;
    const DestroyFn = *const fn (std.mem.Allocator, *anyopaque) void;
    const Allocation = struct {
        object: *anyopaque,
        size: usize,
        marked: bool = false,
        trace: TraceFn,
        destroy: DestroyFn,
    };

    backing: std.mem.Allocator,
    /// Compiler/session allocations remain phase-owned. Managed runtime
    /// objects allocated with create/createTraced are independently swept.
    arena: std.heap.ArenaAllocator,
    bytes_allocated: usize = 0,
    allocations: usize = 0,
    live_allocations: usize = 0,
    collections: usize = 0,
    collection_threshold: usize = 1024,
    stress: bool = false,
    roots: std.ArrayListUnmanaged(*anyopaque) = .empty,
    marked: std.ArrayListUnmanaged(*anyopaque) = .empty,
    managed: std.ArrayListUnmanaged(Allocation) = .empty,

    pub fn init(backing: std.mem.Allocator) Collector {
        return .{ .backing = backing, .arena = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn initWithOptions(backing: std.mem.Allocator, options: Options) Collector {
        return .{
            .backing = backing,
            .arena = std.heap.ArenaAllocator.init(backing),
            .collection_threshold = @max(options.collection_threshold, 1),
            .stress = options.stress,
        };
    }

    pub fn deinit(self: *Collector) void {
        for (self.managed.items) |allocation| allocation.destroy(self.backing, allocation.object);
        self.managed.deinit(self.arena.child_allocator);
        self.roots.deinit(self.arena.child_allocator);
        self.marked.deinit(self.arena.child_allocator);
        self.arena.deinit();
    }

    pub fn allocator(self: *Collector) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn create(self: *Collector, comptime T: type) !*T {
        return self.createTraced(T, null);
    }

    /// Allocate a managed object with an explicit destructor. This is used by
    /// runtime values whose payload owns auxiliary storage (for example UTF-8
    /// strings) so sweep releases both the object and its payload.
    pub fn createManaged(self: *Collector, comptime T: type, comptime destroy_fn: *const fn (std.mem.Allocator, *T) void) !*T {
        try self.safepoint();
        const VTable = struct {
            fn trace(_: *Collector, _: *anyopaque) anyerror!void {}
            fn destroy(memory: std.mem.Allocator, object: *anyopaque) void {
                destroy_fn(memory, @ptrCast(@alignCast(object)));
            }
        };
        const value = try self.backing.create(T);
        errdefer self.backing.destroy(value);
        try self.managed.append(self.arena.child_allocator, .{
            .object = @ptrCast(value),
            .size = @sizeOf(T),
            .trace = VTable.trace,
            .destroy = VTable.destroy,
        });
        self.bytes_allocated += @sizeOf(T);
        self.allocations += 1;
        self.live_allocations += 1;
        return value;
    }

    pub fn createTraced(self: *Collector, comptime T: type, comptime trace_children: ?*const fn (*Collector, *T) anyerror!void) !*T {
        try self.safepoint();
        const VTable = struct {
            fn trace(collector: *Collector, object: *anyopaque) anyerror!void {
                if (trace_children) |trace_fn| try trace_fn(collector, @ptrCast(@alignCast(object)));
            }
            fn destroy(memory: std.mem.Allocator, object: *anyopaque) void {
                memory.destroy(@as(*T, @ptrCast(@alignCast(object))));
            }
        };
        const value = try self.backing.create(T);
        errdefer self.backing.destroy(value);
        try self.managed.append(self.arena.child_allocator, .{
            .object = @ptrCast(value),
            .size = @sizeOf(T),
            .trace = VTable.trace,
            .destroy = VTable.destroy,
        });
        self.bytes_allocated += @sizeOf(T);
        self.allocations += 1;
        self.live_allocations += 1;
        return value;
    }

    pub fn addRoot(self: *Collector, root: *anyopaque) !void {
        for (self.roots.items) |existing| if (existing == root) return;
        try self.roots.append(self.arena.child_allocator, root);
    }

    /// Roll back an initialized object which has not been published to user code.
    /// The caller must not retain handles or child references to this object.
    pub fn discardUnpublished(self: *Collector, object: *anyopaque) void {
        self.removeRoot(object);
        for (self.managed.items, 0..) |allocation, index| {
            if (allocation.object != object) continue;
            allocation.destroy(self.backing, object);
            self.bytes_allocated -= allocation.size;
            self.live_allocations -= 1;
            _ = self.managed.swapRemove(index);
            return;
        }
    }

    pub fn removeRoot(self: *Collector, root: *anyopaque) void {
        for (self.roots.items, 0..) |item, index| {
            if (item == root) {
                _ = self.roots.swapRemove(index);
                return;
            }
        }
    }

    pub fn safepoint(self: *Collector) !void {
        if (self.stress or self.live_allocations >= self.collection_threshold) try self.collect();
    }

    pub fn writeBarrier(self: *Collector, parent: *anyopaque, child: *anyopaque) !void {
        if (self.isMarked(parent)) try self.mark(child);
    }

    pub fn statistics(self: *const Collector) Statistics {
        return .{ .bytes = self.bytes_allocated, .allocations = self.allocations, .live = self.live_allocations, .collections = self.collections };
    }

    pub fn mark(self: *Collector, object: *anyopaque) !void {
        for (self.managed.items) |*allocation| {
            if (allocation.object != object) continue;
            if (allocation.marked) return;
            allocation.marked = true;
            try self.marked.append(self.arena.child_allocator, object);
            return;
        }
    }

    pub fn isMarked(self: *const Collector, object: *anyopaque) bool {
        for (self.managed.items) |allocation| if (allocation.object == object) return allocation.marked;
        return false;
    }

    pub fn isManaged(self: *const Collector, object: *anyopaque) bool {
        for (self.managed.items) |allocation| if (allocation.object == object) return true;
        return false;
    }

    pub fn collect(self: *Collector) !void {
        self.collections += 1;
        self.marked.clearRetainingCapacity();
        for (self.managed.items) |*allocation| allocation.marked = false;
        for (self.roots.items) |root| try self.mark(root);

        var work: usize = 0;
        while (work < self.marked.items.len) : (work += 1) {
            const object = self.marked.items[work];
            for (self.managed.items) |allocation| {
                if (allocation.object == object) {
                    try allocation.trace(self, object);
                    break;
                }
            }
        }

        var index: usize = 0;
        while (index < self.managed.items.len) {
            const allocation = self.managed.items[index];
            if (allocation.marked) {
                index += 1;
                continue;
            }
            allocation.destroy(self.backing, allocation.object);
            self.bytes_allocated -= allocation.size;
            self.live_allocations -= 1;
            _ = self.managed.swapRemove(index);
        }
    }
};

test "mark-sweep collector reclaims unreachable objects" {
    var collector = Collector.init(std.testing.allocator);
    defer collector.deinit();
    const rooted = try collector.create(u64);
    rooted.* = 42;
    _ = try collector.create(u64);
    try collector.addRoot(@ptrCast(rooted));
    try collector.collect();
    try std.testing.expect(collector.isMarked(@ptrCast(rooted)));
    try std.testing.expectEqual(@as(usize, 1), collector.live_allocations);
    collector.removeRoot(@ptrCast(rooted));
    try collector.collect();
    try std.testing.expectEqual(@as(usize, 0), collector.live_allocations);
}

test "tracing preserves children reachable from a root" {
    const Node = struct { child: ?*@This() = null };
    const Tracer = struct {
        fn trace(collector: *Collector, node: *Node) !void {
            if (node.child) |child| try collector.mark(@ptrCast(child));
        }
    };
    var collector = Collector.init(std.testing.allocator);
    defer collector.deinit();
    const parent = try collector.createTraced(Node, Tracer.trace);
    const child = try collector.createTraced(Node, Tracer.trace);
    parent.* = .{ .child = child };
    child.* = .{};
    try collector.addRoot(@ptrCast(parent));
    try collector.collect();
    try std.testing.expectEqual(@as(usize, 2), collector.live_allocations);
}

test "tiny threshold and cycles reclaim safely" {
    const Node = struct { child: ?*@This() = null };
    const Tracer = struct {
        fn trace(collector: *Collector, node: *Node) !void {
            if (node.child) |child| try collector.mark(@ptrCast(child));
        }
    };
    var collector = Collector.initWithOptions(std.testing.allocator, .{ .collection_threshold = 2 });
    defer collector.deinit();
    const first = try collector.createTraced(Node, Tracer.trace);
    try collector.addRoot(@ptrCast(first));
    const second = try collector.createTraced(Node, Tracer.trace);
    first.* = .{ .child = second };
    second.* = .{ .child = first };
    try collector.collect();
    try std.testing.expectEqual(@as(usize, 2), collector.statistics().live);
    collector.removeRoot(@ptrCast(first));
    try collector.collect();
    try std.testing.expectEqual(@as(usize, 0), collector.statistics().live);
}

test "managed destructor releases auxiliary payloads during sweep" {
    const Payload = struct { bytes: []u8 };
    const Hooks = struct {
        fn destroy(allocator: std.mem.Allocator, payload: *Payload) void {
            allocator.free(payload.bytes);
            allocator.destroy(payload);
        }
    };
    var collector = Collector.init(std.testing.allocator);
    defer collector.deinit();
    const payload = try collector.createManaged(Payload, Hooks.destroy);
    payload.* = .{ .bytes = try std.testing.allocator.dupe(u8, "payload") };
    try std.testing.expectEqual(@as(usize, 1), collector.statistics().live);
    try collector.collect();
    try std.testing.expectEqual(@as(usize, 0), collector.statistics().live);
}
