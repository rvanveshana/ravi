const std = @import("std");
const bytecode = @import("ravi_bytecode");

pub const Breakpoint = struct { id: usize, instruction: usize, enabled: bool = true };
pub const Frame = struct { function: []const u8, instruction: usize, line: usize };
pub const Request = union(enum) { set_breakpoint: usize, continue_execution, stack_trace };
pub const Response = union(enum) { stopped: usize, running, frames: []const Frame, error_message: []const u8 };
pub const Debugger = struct {
    allocator: std.mem.Allocator,
    breakpoints: std.ArrayListUnmanaged(Breakpoint) = .empty,
    pub fn init(allocator: std.mem.Allocator) Debugger {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Debugger) void {
        self.breakpoints.deinit(self.allocator);
    }
    pub fn addBreakpoint(self: *Debugger, instruction: usize) !usize {
        const id = self.breakpoints.items.len;
        try self.breakpoints.append(self.allocator, .{ .id = id, .instruction = instruction });
        return id;
    }
    pub fn removeBreakpoint(self: *Debugger, id: usize) void {
        for (self.breakpoints.items, 0..) |point, i| {
            if (point.id == id) {
                _ = self.breakpoints.orderedRemove(i);
                return;
            }
        }
    }
    pub fn shouldStop(self: *const Debugger, instruction: usize) bool {
        for (self.breakpoints.items) |point| if (point.enabled and point.instruction == instruction) return true;
        return false;
    }
    pub fn location(chunk: *const bytecode.Chunk, instruction: usize) ?bytecode.SourceLocation {
        if (instruction >= chunk.source_map.items.len) return null;
        return chunk.source_map.items[instruction];
    }
    pub fn handle(self: *Debugger, request: Request) !Response {
        return switch (request) {
            .set_breakpoint => |instruction| .{ .stopped = try self.addBreakpoint(instruction) },
            .continue_execution => .running,
            .stack_trace => .{ .frames = &.{} },
        };
    }
};
