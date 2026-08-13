const std = @import("std");
const heap = @import("heap.zig");
const errors = @import("errors.zig");

pub fn push(self: anytype, value: @import("ravi_vm_value").Value) !void {
    if (self.stack_top == self.stack.len) {
        const next = if (self.stack.len == 0) 256 else self.stack.len * 2;
        self.stack = try self.allocator.realloc(self.stack, next);
    }
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

pub fn ensureCallCapacity(self: anytype) !void {
    if (self.frame_top + 1 >= self.frames.len) {
        const old_len = self.frames.len;
        self.frames = try self.allocator.realloc(self.frames, self.frames.len * 2);
        for (self.frames[old_len..]) |*frame| frame.* = .{};
    }
    if (self.trace_count >= self.trace.len) self.trace = try self.allocator.realloc(self.trace, self.trace.len * 2);
}

pub fn handleFault(self: anytype, ip: *usize) bool {
    if (!self.handler_active) return false;
    self.last_exception = @import("ravi_vm_value").Value.fromInt(1);
    self.handler_active = false;
    self.stack_top = self.handler_stack_top;
    push(self, self.last_exception) catch return false;
    unwindFrames(self, self.handler_frame_top);
    self.trace_count = self.handler_trace_count;
    ip.* = if (self.handler_ip == 0) 0 else self.handler_ip - 1;
    return true;
}

pub fn internString(self: anytype, text: []const u8) errors.RuntimeError!@import("ravi_vm_value").Value {
    const Value = @import("ravi_vm_value").Value;
    for (self.strings.items, 0..) |existing, slot| {
        if (!self.collector.isManaged(@ptrCast(existing))) continue;
        if (std.mem.eql(u8, existing.bytes, text)) return Value.fromHandle(.string, slot) catch unreachable;
    }
    // The backing array grows with the allocator; a fixed string-count cap
    // made otherwise valid programs fail arbitrarily at 1,000 interned
    // strings. `Value.fromHandle` still enforces the representable handle
    // range, and allocation failures propagate as OutOfMemory.
    const owned = try self.allocator.dupe(u8, text);
    errdefer self.allocator.free(owned);
    const managed = self.collector.createManaged(heap.ManagedString, heap.destroyString) catch return error.OutOfMemory;
    managed.* = .{ .bytes = owned };
    errdefer self.collector.removeRoot(@ptrCast(managed));
    self.collector.addRoot(@ptrCast(managed)) catch return error.OutOfMemory;
    self.gc_roots.append(self.allocator, @ptrCast(managed)) catch return error.OutOfMemory;
    const slot = self.strings.items.len;
    try self.strings.append(self.allocator, managed);
    return Value.fromHandle(.string, slot) catch unreachable;
}

pub fn clearContainers(self: anytype) void {
    for (self.arrays[0..self.array_count]) |array| self.collector.removeRoot(@ptrCast(array));
    for (self.dicts[0..self.dict_count]) |dict| self.collector.removeRoot(@ptrCast(dict));
    for (self.instances[0..self.instance_count]) |instance| self.collector.removeRoot(@ptrCast(instance));
    self.array_count = 0;
    self.dict_count = 0;
    self.instance_count = 0;
}

pub fn clearFrames(self: anytype) void {
    var index: usize = 0;
    while (index <= self.frame_top and index < self.frames.len) : (index += 1) self.frames[index].deinit(self.allocator);
    self.frame_top = 0;
}

pub fn unwindFrames(self: anytype, target: usize) void {
    while (self.frame_top > target) {
        self.frames[self.frame_top].deinit(self.allocator);
        self.frame_top -= 1;
    }
}

pub fn clearClosures(self: anytype) void {
    for (self.closures[0..self.closure_count]) |closure| self.collector.removeRoot(@ptrCast(closure));
    for (self.cells[0..self.cell_count]) |cell| self.collector.removeRoot(@ptrCast(cell));
    self.closure_count = 0;
}

pub fn clearStrings(self: anytype) void {
    for (self.gc_roots.items) |root| self.collector.removeRoot(root);
    self.gc_roots.clearRetainingCapacity();
    self.strings.clearRetainingCapacity();
}

pub fn deinit(self: anytype) void {
    clearContainers(self);
    clearFrames(self);
    clearClosures(self);
    self.allocator.free(self.stack);
    self.allocator.free(self.frames);
    self.allocator.free(self.trace);
    if (self.arrays.len != 0) self.allocator.free(self.arrays);
    if (self.dicts.len != 0) self.allocator.free(self.dicts);
    if (self.closures.len != 0) self.allocator.free(self.closures);
    if (self.cells.len != 0) self.allocator.free(self.cells);
    if (self.instances.len != 0) self.allocator.free(self.instances);
    clearStrings(self);
    self.strings.deinit(self.allocator);
    self.gc_roots.deinit(self.allocator);
}
