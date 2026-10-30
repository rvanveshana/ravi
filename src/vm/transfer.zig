const std = @import("std");
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const storage = @import("object_storage.zig");
const collections = @import("ravi_vm_collections");
const state = @import("state_helpers.zig");
const Kind = enum { scalar, string, array, dictionary, closure, cell, instance, exception, channel };
const Node = struct { kind: Kind = .scalar, value: Value = Value.nil(), meta: usize = 0, bytes: []const u8 = "", edges: []usize = &.{} };

/// Bounded immutable copy graph. IDs preserve aliases and cycles within a
/// transfer, while mutable objects never share a heap across VM boundaries.
pub const Packet = struct {
    arena: std.heap.ArenaAllocator,
    nodes: std.ArrayListUnmanaged(Node) = .empty,
    roots: []usize = &.{},
    seen: std.AutoHashMapUnmanaged(u64, usize) = .empty,
    bytes: usize = 0,
    allow_channels: bool = true,

    pub fn create(vm: anytype, values: []const Value) Error!*Packet {
        return createOptions(vm, values, true);
    }
    pub fn createMessage(vm: anytype, values: []const Value) Error!*Packet {
        return createOptions(vm, values, false);
    }
    fn createOptions(vm: anytype, values: []const Value, channels: bool) Error!*Packet {
        const owner = std.heap.smp_allocator;
        const self = owner.create(Packet) catch return error.OutOfMemory;
        self.* = .{ .arena = std.heap.ArenaAllocator.init(owner), .allow_channels = channels };
        errdefer self.destroy();
        self.roots = self.arena.allocator().alloc(usize, values.len) catch return error.OutOfMemory;
        for (values, 0..) |value, i| self.roots[i] = try self.capture(vm, value, 0);
        return self;
    }

    pub fn destroy(self: *Packet) void {
        for (self.nodes.items) |node| if (node.kind == .channel) {
            const shared: *@import("shared_channel.zig").Shared = @ptrFromInt(node.meta);
            shared.release();
        };
        self.arena.deinit();
        std.heap.smp_allocator.destroy(self);
    }

    fn charge(self: *Packet, bytes: usize) Error!void {
        self.bytes = std.math.add(usize, self.bytes, bytes) catch return error.TransferLimit;
        if (self.bytes > 8 * 1024 * 1024) return error.TransferLimit;
    }

    fn capture(self: *Packet, vm: anytype, value: Value, depth: usize) Error!usize {
        if (self.seen.get(@intFromEnum(value))) |id| return id;
        if (depth > 256 or self.nodes.items.len >= 65536) return error.TransferLimit;
        if (value.isObject()) return error.UnsupportedTransfer;
        const allocator = self.arena.allocator();
        const id = self.nodes.items.len;
        try self.charge(@sizeOf(Node));
        self.nodes.append(allocator, .{ .value = value }) catch return error.OutOfMemory;
        self.seen.put(allocator, @intFromEnum(value), id) catch return error.OutOfMemory;
        if (!value.isHandle()) return id;
        const kind = value.handleKind() orelse return error.UnsupportedTransfer;
        const index = value.handleIndex().?;
        if (kind == .function) return id;
        if (kind == .channel) {
            if (!self.allow_channels) return error.UnsupportedTransfer;
            const shared = try @import("shared_channel.zig").resolve(vm, value);
            shared.retain();
            self.nodes.items[id] = .{ .kind = .channel, .meta = @intFromPtr(shared) };
            return id;
        }
        if (storage.objectPointer(vm, value) == null) return error.UnsupportedTransfer;
        var node = Node{ .value = value };
        var values: []const Value = &.{};
        switch (kind) {
            .string => {
                node.kind = .string;
                node.bytes = vm.strings.items[index].bytes;
            },
            .array, .tuple, .set => {
                node.kind = .array;
                node.meta = @intFromEnum(kind);
                values = vm.arrays[index].items[0..vm.arrays[index].len];
            },
            .closure => {
                node.kind = .closure;
                node.meta = vm.closures[index].function_index;
                values = vm.closures[index].captures;
            },
            .cell => {
                node.kind = .cell;
                values = @as(*const [1]Value, @ptrCast(&vm.cells[index].value));
            },
            .exception => {
                node.kind = .exception;
                node.bytes = vm.exceptions[index].name;
            },
            .dictionary, .instance => {
                node.kind = if (kind == .dictionary) .dictionary else .instance;
                if (kind == .instance) node.meta = vm.instances[index].class_index;
                const dict = if (kind == .dictionary) vm.dicts[index] else &vm.instances[index].fields;
                try self.charge(dict.len * 2 * @sizeOf(Value));
                const pairs = allocator.alloc(Value, dict.len * 2) catch return error.OutOfMemory;
                var cursor: usize = 0;
                for (dict.occupied, 0..) |occupied, i| if (occupied) {
                    pairs[cursor] = dict.keys[i];
                    pairs[cursor + 1] = dict.values[i];
                    cursor += 2;
                };
                values = pairs;
            },
            else => return error.UnsupportedTransfer,
        }
        try self.charge(node.bytes.len + values.len * @sizeOf(usize));
        node.bytes = allocator.dupe(u8, node.bytes) catch return error.OutOfMemory;
        node.edges = allocator.alloc(usize, values.len) catch return error.OutOfMemory;
        for (values, 0..) |child, i| node.edges[i] = try self.capture(vm, child, depth + 1);
        self.nodes.items[id] = node;
        return id;
    }

    pub fn restore(self: *const Packet, vm: anytype) Error![]Value {
        const counts = .{ vm.array_count, vm.dict_count, vm.closure_count, vm.cell_count, vm.instance_count, vm.exception_count, vm.strings.items.len, vm.gc_roots.items.len, vm.channels.items.len };
        errdefer {
            for (vm.gc_roots.items[counts[7]..]) |root| {
                vm.collector.removeRoot(root);
                vm.collector.discardUnpublished(root);
            }
            vm.gc_roots.items.len = counts[7];
            vm.array_count = counts[0];
            vm.dict_count = counts[1];
            vm.closure_count = counts[2];
            vm.cell_count = counts[3];
            vm.instance_count = counts[4];
            vm.exception_count = counts[5];
            vm.strings.items.len = counts[6];
            for (vm.channels.items[counts[8]..]) |channel| channel.release();
            vm.channels.items.len = counts[8];
        }
        const memo = vm.allocator.alloc(?Value, self.nodes.items.len) catch return error.OutOfMemory;
        defer vm.allocator.free(memo);
        @memset(memo, null);
        const values = vm.allocator.alloc(Value, self.roots.len) catch return error.OutOfMemory;
        errdefer vm.allocator.free(values);
        for (self.roots, 0..) |id, i| values[i] = try self.materialize(vm, memo, id);
        return values;
    }

    fn materialize(self: *const Packet, vm: anytype, memo: []?Value, id: usize) Error!Value {
        if (memo[id]) |value| return value;
        const node = self.nodes.items[id];
        var slot: usize = 0;
        const result = switch (node.kind) {
            .channel => try @import("shared_channel.zig").attach(vm, @ptrFromInt(node.meta)),
            .scalar => node.value,
            .string => try state.internString(vm, node.bytes),
            .array => blk: {
                slot = try storage.newArray(vm);
                break :blk try makeHandle(@enumFromInt(node.meta), slot);
            },
            .dictionary => blk: {
                slot = try storage.newDict(vm);
                break :blk try makeHandle(.dictionary, slot);
            },
            .closure => blk: {
                slot = try storage.newClosure(vm, node.meta, node.edges.len);
                break :blk try makeHandle(.closure, slot);
            },
            .cell => blk: {
                slot = try storage.newCell(vm, Value.nil());
                break :blk try makeHandle(.cell, slot);
            },
            .instance => blk: {
                slot = try storage.newInstance(vm, node.meta);
                break :blk try makeHandle(.instance, slot);
            },
            .exception => blk: {
                slot = try storage.newException(vm, node.bytes);
                break :blk try makeHandle(.exception, slot);
            },
        };
        memo[id] = result;
        switch (node.kind) {
            .array => for (node.edges) |child| try collections.append(vm.arrays[slot], try self.materialize(vm, memo, child)),
            .closure => for (node.edges, 0..) |child, i| {
                vm.closures[slot].captures[i] = try self.materialize(vm, memo, child);
            },
            .cell => vm.cells[slot].value = try self.materialize(vm, memo, node.edges[0]),
            .dictionary, .instance => {
                const dict = if (node.kind == .dictionary) vm.dicts[slot] else &vm.instances[slot].fields;
                var i: usize = 0;
                while (i < node.edges.len) : (i += 2) try collections.put(dict, try self.materialize(vm, memo, node.edges[i]), try self.materialize(vm, memo, node.edges[i + 1]));
            },
            else => {},
        }
        return result;
    }
};

fn makeHandle(kind: Value.ObjectKind, index: usize) Error!Value {
    return Value.fromHandle(kind, index) catch return error.InvalidInstruction;
}
