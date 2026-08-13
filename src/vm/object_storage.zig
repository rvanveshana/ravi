const std = @import("std");
const errors = @import("errors.zig");
const heap = @import("heap.zig");
const collections = @import("ravi_vm_collections");
const frames = @import("frames.zig");
const bytecode = @import("ravi_bytecode");
const Value = @import("ravi_vm_value").Value;

pub fn ensure(allocator: std.mem.Allocator, comptime T: type, storage: *[]T, required: usize) !void {
    if (required <= storage.len) return;
    var next = @max(storage.len, 8);
    while (next < required) next = std.math.mul(usize, next, 2) catch return error.OutOfMemory;
    storage.* = if (storage.len == 0) try allocator.alloc(T, next) else try allocator.realloc(storage.*, next);
}

pub fn deinit(allocator: std.mem.Allocator, storage: anytype) void {
    if (storage.len != 0) allocator.free(storage);
}

pub fn newArray(self: anytype) errors.RuntimeError!usize {
    try ensure(self.allocator, *heap.ManagedArray, &self.arrays, self.array_count + 1);
    const slot = self.array_count;
    const array = self.collector.createManaged(heap.ManagedArray, heap.destroyArray) catch return error.OutOfMemory;
    array.* = collections.Array.init(self.allocator);
    self.collector.addRoot(@ptrCast(array)) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, @ptrCast(array)) catch return error.OutOfMemory;
    self.arrays[slot] = array;
    self.array_count += 1;
    return slot;
}

pub fn newDict(self: anytype) errors.RuntimeError!usize {
    try ensure(self.allocator, *heap.ManagedDict, &self.dicts, self.dict_count + 1);
    const slot = self.dict_count;
    const dict = self.collector.createManaged(heap.ManagedDict, heap.destroyDict) catch return error.OutOfMemory;
    dict.* = collections.Dict.init(self.allocator);
    self.collector.addRoot(@ptrCast(dict)) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, @ptrCast(dict)) catch return error.OutOfMemory;
    self.dicts[slot] = dict;
    self.dict_count += 1;
    return slot;
}

pub fn newClosure(self: anytype, function_index: usize, capture_count: usize) errors.RuntimeError!usize {
    try ensure(self.allocator, *heap.ManagedClosure, &self.closures, self.closure_count + 1);
    const slot = self.closure_count;
    const closure = self.collector.createManaged(heap.ManagedClosure, heap.destroyClosure) catch return error.OutOfMemory;
    closure.* = frames.Closure.init(self.allocator, function_index, capture_count) catch return error.OutOfMemory;
    self.collector.addRoot(@ptrCast(closure)) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, @ptrCast(closure)) catch return error.OutOfMemory;
    self.closures[slot] = closure;
    self.closure_count += 1;
    return slot;
}

pub fn newCell(self: anytype, value: @import("ravi_vm_value").Value) errors.RuntimeError!usize {
    try ensure(self.allocator, *heap.ManagedCell, &self.cells, self.cell_count + 1);
    const slot = self.cell_count;
    const cell = self.collector.createManaged(heap.ManagedCell, heap.destroyCell) catch return error.OutOfMemory;
    cell.* = .{ .value = value };
    self.collector.addRoot(@ptrCast(cell)) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, @ptrCast(cell)) catch return error.OutOfMemory;
    self.cells[slot] = cell;
    self.cell_count += 1;
    return slot;
}

pub fn newInstance(self: anytype, class_index: usize) errors.RuntimeError!usize {
    try ensure(self.allocator, *heap.ManagedInstance, &self.instances, self.instance_count + 1);
    const slot = self.instance_count;
    const instance = self.collector.createManaged(heap.ManagedInstance, heap.destroyInstance) catch return error.OutOfMemory;
    instance.* = .{ .class_index = class_index, .fields = collections.Dict.init(self.allocator) };
    self.collector.addRoot(@ptrCast(instance)) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, @ptrCast(instance)) catch return error.OutOfMemory;
    self.instances[slot] = instance;
    self.instance_count += 1;
    return slot;
}

/// Tests an instance against a class or any of its single-inheritance bases.
/// Keeping this beside instance allocation gives VM operators and debugger
/// inspectors one bounds-checked ancestry implementation.
pub fn instanceIsA(instance: *const heap.ManagedInstance, classes: []const bytecode.ClassInfo, target: usize) bool {
    return bytecode.ClassInfo.inheritsFrom(classes, instance.class_index, target);
}

/// Rebuild collector roots from live VM values before a collection. Handles
/// are indices into the VM tables, so this gives the collector precise roots
/// without exposing table internals to the generic GC implementation.
pub fn refreshRoots(self: anytype) errors.RuntimeError!void {
    for (self.gc_roots.items) |root| self.collector.removeRoot(root);
    self.gc_roots.clearRetainingCapacity();
    var seen = std.AutoHashMap(u64, void).init(self.allocator);
    defer seen.deinit();
    for (self.stack[0..self.stack_top]) |value| try markValue(self, value, &seen);
    for (self.frames[0..@min(self.frame_top + 1, self.frames.len)]) |frame| {
        for (frame.locals) |value| try markValue(self, value, &seen);
        for (frame.captures) |value| try markValue(self, value, &seen);
    }
    try markValue(self, self.last_exception, &seen);
}

fn markValue(self: anytype, value: Value, seen: *std.AutoHashMap(u64, void)) errors.RuntimeError!void {
    const kind = value.handleKind() orelse return;
    const index = value.handleIndex().?;
    const key = (@as(u64, @intFromEnum(kind)) << 40) | @as(u64, @intCast(index));
    if (seen.contains(key)) return;
    try seen.put(key, {});
    switch (kind) {
        .string => if (index < self.strings.items.len and self.collector.isManaged(@ptrCast(self.strings.items[index]))) try addRoot(self, @ptrCast(self.strings.items[index])) else return error.InvalidInstruction,
        .array, .tuple, .set => {
            if (index >= self.array_count or !self.collector.isManaged(@ptrCast(self.arrays[index]))) return error.InvalidInstruction;
            try addRoot(self, @ptrCast(self.arrays[index]));
            for (self.arrays[index].items[0..self.arrays[index].len]) |child| try markValue(self, child, seen);
        },
        .dictionary => {
            if (index >= self.dict_count or !self.collector.isManaged(@ptrCast(self.dicts[index]))) return error.InvalidInstruction;
            try addRoot(self, @ptrCast(self.dicts[index]));
            for (self.dicts[index].occupied, 0..) |occupied, slot| if (occupied) {
                try markValue(self, self.dicts[index].keys[slot], seen);
                try markValue(self, self.dicts[index].values[slot], seen);
            };
        },
        .closure => {
            if (index >= self.closure_count or !self.collector.isManaged(@ptrCast(self.closures[index]))) return error.InvalidInstruction;
            try addRoot(self, @ptrCast(self.closures[index]));
            for (self.closures[index].captures) |child| try markValue(self, child, seen);
        },
        .cell => {
            if (index >= self.cell_count or !self.collector.isManaged(@ptrCast(self.cells[index]))) return error.InvalidInstruction;
            try addRoot(self, @ptrCast(self.cells[index]));
            try markValue(self, self.cells[index].value, seen);
        },
        .instance => {
            if (index >= self.instance_count or !self.collector.isManaged(@ptrCast(self.instances[index]))) return error.InvalidInstruction;
            try addRoot(self, @ptrCast(self.instances[index]));
            for (self.instances[index].fields.occupied, 0..) |occupied, slot| if (occupied) {
                try markValue(self, self.instances[index].fields.keys[slot], seen);
                try markValue(self, self.instances[index].fields.values[slot], seen);
            };
        },
        else => {},
    }
}

fn addRoot(self: anytype, pointer: *anyopaque) errors.RuntimeError!void {
    self.collector.addRoot(pointer) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, pointer) catch return error.OutOfMemory;
}

pub fn writeBarrierValue(self: anytype, parent: Value, child: Value) errors.RuntimeError!void {
    const parent_pointer = objectPointer(self, parent) orelse return;
    const child_pointer = objectPointer(self, child) orelse return;
    self.collector.writeBarrier(parent_pointer, child_pointer) catch return error.OutOfMemory;
}

fn objectPointer(self: anytype, value: Value) ?*anyopaque {
    const kind = value.handleKind() orelse return null;
    const index = value.handleIndex().?;
    return switch (kind) {
        .string => if (index < self.strings.items.len and self.collector.isManaged(@ptrCast(self.strings.items[index]))) @ptrCast(self.strings.items[index]) else null,
        .array, .tuple, .set => if (index < self.array_count and self.collector.isManaged(@ptrCast(self.arrays[index]))) @ptrCast(self.arrays[index]) else null,
        .dictionary => if (index < self.dict_count and self.collector.isManaged(@ptrCast(self.dicts[index]))) @ptrCast(self.dicts[index]) else null,
        .closure => if (index < self.closure_count and self.collector.isManaged(@ptrCast(self.closures[index]))) @ptrCast(self.closures[index]) else null,
        .cell => if (index < self.cell_count and self.collector.isManaged(@ptrCast(self.cells[index]))) @ptrCast(self.cells[index]) else null,
        .instance => if (index < self.instance_count and self.collector.isManaged(@ptrCast(self.instances[index]))) @ptrCast(self.instances[index]) else null,
        else => null,
    };
}
