const std = @import("std");
const Value = @import("ravi_vm_value").Value;

pub const Frame = struct {
    return_ip: usize = 0,
    base: usize = 0,
    locals: []Value = &.{},
    captures: []const Value = &.{},
    /// Owning receiver class for method frames; null for free functions.
    owner_class: ?usize = null,

    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        if (self.locals.len != 0) allocator.free(self.locals);
        self.* = .{};
    }

    pub fn ensureLocals(self: *Frame, allocator: std.mem.Allocator, required: usize) !void {
        if (required <= self.locals.len) return;
        var next = @max(self.locals.len, 8);
        while (next < required) next = std.math.mul(usize, next, 2) catch return error.OutOfMemory;
        const old_len = self.locals.len;
        self.locals = if (old_len == 0) try allocator.alloc(Value, next) else try allocator.realloc(self.locals, next);
        @memset(self.locals[old_len..], Value.nil());
    }
};

pub const Closure = struct {
    function_index: usize = 0,
    captures: []Value = &.{},

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        if (self.captures.len != 0) allocator.free(self.captures);
        self.* = .{};
    }

    pub fn init(allocator: std.mem.Allocator, function_index: usize, capture_count: usize) !Closure {
        const captures = try allocator.alloc(Value, capture_count);
        return .{ .function_index = function_index, .captures = captures };
    }
};

pub const Cell = struct { value: Value };
