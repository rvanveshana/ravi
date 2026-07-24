const std = @import("std");
const bytecode = @import("ravi_bytecode");

pub const Breakpoint = struct { id: usize, instruction: usize, enabled: bool = true };
pub const Frame = struct { function: []const u8, instruction: usize, line: usize };
pub const Variable = struct { name: []const u8, value: i64, mutable: bool = true };
pub const Scope = struct { name: []const u8, variables: []const Variable };
pub const Request = union(enum) { set_breakpoint: usize, continue_execution, stack_trace };
pub const Response = union(enum) { stopped: usize, running, frames: []const Frame, error_message: []const u8 };
pub const StepMode = enum { none, into, over, out };
pub const Debugger = struct {
    allocator: std.mem.Allocator,
    breakpoints: std.ArrayListUnmanaged(Breakpoint) = .empty,
    frames: std.ArrayListUnmanaged(Frame) = .empty,
    step_mode: StepMode = .none,
    step_depth: usize = 0,
    step_instruction: usize = 0,
    paused: bool = false,
    paused_instruction: ?usize = null,
    break_on_throw: bool = false,
    break_on_unhandled: bool = true,
    pub fn init(allocator: std.mem.Allocator) Debugger {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Debugger) void {
        self.breakpoints.deinit(self.allocator);
        self.frames.deinit(self.allocator);
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
    pub fn setBreakpointEnabled(self: *Debugger, id: usize, enabled: bool) !void {
        for (self.breakpoints.items) |*point| {
            if (point.id == id) {
                point.enabled = enabled;
                return;
            }
        }
        return error.UnknownBreakpoint;
    }
    pub fn shouldStop(self: *const Debugger, instruction: usize) bool {
        if (self.paused) return true;
        for (self.breakpoints.items) |point| if (point.enabled and point.instruction == instruction) return true;
        return false;
    }

    pub fn onInstruction(self: *Debugger, instruction: usize, depth: usize) bool {
        var stop = self.shouldStop(instruction);
        if (!stop and instruction != self.step_instruction) stop = switch (self.step_mode) {
            .none => false,
            .into => true,
            .over => depth <= self.step_depth,
            .out => depth < self.step_depth,
        };
        if (stop) {
            self.paused = true;
            self.paused_instruction = instruction;
            self.step_mode = .none;
        }
        return stop;
    }
    pub fn addSourceBreakpoint(self: *Debugger, chunk: *const bytecode.Chunk, line: usize) !usize {
        var candidate: ?usize = null;
        for (chunk.source_map.items, 0..) |location_value, instruction| {
            if (location_value.line == line) return self.addBreakpoint(instruction);
            if (location_value.line > line and candidate == null) candidate = instruction;
        }
        if (candidate) |instruction| return self.addBreakpoint(instruction);
        return error.NoExecutableLocation;
    }
    pub fn requestPause(self: *Debugger) void {
        self.paused = true;
    }
    pub fn continueExecution(self: *Debugger) void {
        self.paused = false;
        self.paused_instruction = null;
        self.step_mode = .none;
    }
    pub fn step(self: *Debugger, mode: StepMode) void {
        self.beginStep(mode, 0, 0);
    }
    pub fn beginStep(self: *Debugger, mode: StepMode, depth: usize, instruction: usize) void {
        self.paused = false;
        self.paused_instruction = null;
        self.step_mode = mode;
        self.step_depth = depth;
        self.step_instruction = instruction;
    }
    pub fn setExceptionBreakpoints(self: *Debugger, on_throw: bool, on_unhandled: bool) void {
        self.break_on_throw = on_throw;
        self.break_on_unhandled = on_unhandled;
    }
    pub fn shouldBreakOnException(self: *const Debugger, handled: bool) bool {
        return self.break_on_throw or (!handled and self.break_on_unhandled);
    }
    pub fn evaluate(scopes: []const Scope, name: []const u8) !i64 {
        for (scopes) |scope| for (scope.variables) |variable| {
            if (std.mem.eql(u8, variable.name, name)) return variable.value;
        };
        return error.UnknownVariable;
    }
    pub fn updateFrames(self: *Debugger, frames: []const Frame) !void {
        self.frames.clearRetainingCapacity();
        try self.frames.appendSlice(self.allocator, frames);
    }
    pub fn location(chunk: *const bytecode.Chunk, instruction: usize) ?bytecode.SourceLocation {
        if (instruction >= chunk.source_map.items.len) return null;
        return chunk.source_map.items[instruction];
    }
    pub fn pausedLocation(self: *const Debugger, chunk: *const bytecode.Chunk) ?bytecode.SourceLocation {
        return if (self.paused_instruction) |instruction| location(chunk, instruction) else null;
    }
    pub fn handle(self: *Debugger, request: Request) !Response {
        return switch (request) {
            .set_breakpoint => |instruction| .{ .stopped = try self.addBreakpoint(instruction) },
            .continue_execution => blk: {
                self.continueExecution();
                break :blk .running;
            },
            .stack_trace => .{ .frames = self.frames.items },
        };
    }
};

pub fn stackEffect(instruction: bytecode.Instruction) i16 {
    return switch (instruction.op) {
        .constant, .make_string, .make_function, .make_instance, .load_local, .load_capture, .load_capture_ref, .dup => 1,
        .pop, .print, .clear_collection, .reverse_collection, .sort_collection => -1,
        .add, .subtract, .multiply, .divide, .modulo, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or, .index, .contains_collection, .dict_get, .dict_contains, .set_union, .set_intersection, .set_difference => -1,
        .make_array, .make_tuple, .make_set => 1 - @as(i16, @intCast(instruction.operand)),
        .make_dict => 1 - @as(i16, @intCast(instruction.operand * 2)),
        .set_property => -2,
        else => 0,
    };
}

pub fn formatInstruction(buffer: []u8, chunk: *const bytecode.Chunk, instruction: usize) ![]const u8 {
    if (instruction >= chunk.code.items.len) return error.InvalidInstruction;
    const value = chunk.code.items[instruction];
    const location: bytecode.SourceLocation = if (instruction < chunk.source_map.items.len) chunk.source_map.items[instruction] else .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 };
    return std.fmt.bufPrint(buffer, "{d:0>5} {s:<22} {d:>6} stack {d:>3}  @ {d}:{d}", .{ instruction, @tagName(value.op), value.operand, stackEffect(value), location.line, location.column });
}

test "debugger manages instruction breakpoints" {
    var debugger = Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    const id = try debugger.addBreakpoint(7);
    try std.testing.expect(debugger.shouldStop(7));
    try debugger.setBreakpointEnabled(id, false);
    try std.testing.expect(!debugger.shouldStop(7));
    try debugger.setBreakpointEnabled(id, true);
    try std.testing.expect(debugger.shouldStop(7));
    debugger.removeBreakpoint(id);
    try std.testing.expect(!debugger.shouldStop(7));
    try std.testing.expectError(error.UnknownBreakpoint, debugger.setBreakpointEnabled(id, true));
}

test "debugger maps source breakpoints and exposes Ravi frames" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    chunk.setSourceLocation(.{ .start_offset = 0, .end_offset = 1, .line = 7, .column = 3 });
    try chunk.emit(.{ .op = .halt });
    var debugger = Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    _ = try debugger.addSourceBreakpoint(&chunk, 7);
    try std.testing.expect(debugger.shouldStop(0));
    try debugger.updateFrames(&.{.{ .function = "main", .instruction = 0, .line = 7 }});
    const response = try debugger.handle(.stack_trace);
    try std.testing.expectEqual(@as(usize, 1), response.frames.len);
}

test "debugger step modes respect Ravi call depth" {
    var debugger = Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    debugger.beginStep(.over, 2, 10);
    try std.testing.expect(!debugger.onInstruction(11, 3));
    try std.testing.expect(debugger.onInstruction(12, 2));
    try std.testing.expectEqual(@as(?usize, 12), debugger.paused_instruction);
    debugger.continueExecution();
    try std.testing.expect(debugger.paused_instruction == null);
    debugger.beginStep(.out, 2, 12);
    try std.testing.expect(!debugger.onInstruction(13, 2));
    try std.testing.expect(debugger.onInstruction(14, 1));
}

test "debugger resolves retained pause location through source map" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    chunk.setSourceLocation(.{ .start_offset = 8, .end_offset = 9, .line = 12, .column = 4 });
    try chunk.emit(.{ .op = .halt });
    var debugger = Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    _ = try debugger.addBreakpoint(0);
    try std.testing.expect(debugger.onInstruction(0, 0));
    try std.testing.expectEqual(@as(usize, 12), debugger.pausedLocation(&chunk).?.line);
}

test "debugger resolves lines, exceptions, scopes and expressions" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    chunk.setSourceLocation(.{ .start_offset = 4, .end_offset = 5, .line = 4, .column = 1 });
    try chunk.emit(.{ .op = .halt });
    var debugger = Debugger.init(std.testing.allocator);
    defer debugger.deinit();
    _ = try debugger.addSourceBreakpoint(&chunk, 3);
    try std.testing.expect(debugger.shouldStop(0));
    debugger.setExceptionBreakpoints(false, true);
    try std.testing.expect(!debugger.shouldBreakOnException(true));
    try std.testing.expect(debugger.shouldBreakOnException(false));
    const variables = [_]Variable{.{ .name = "answer", .value = 42 }};
    const scopes = [_]Scope{.{ .name = "Locals", .variables = &variables }};
    try std.testing.expectEqual(@as(i64, 42), try Debugger.evaluate(&scopes, "answer"));
    try std.testing.expectError(error.UnknownVariable, Debugger.evaluate(&scopes, "missing"));
}

test "disassembler includes offset opcode effect and source" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    chunk.setSourceLocation(.{ .start_offset = 0, .end_offset = 2, .line = 3, .column = 5 });
    try chunk.emit(.{ .op = .constant, .operand = 42 });
    var buffer: [160]u8 = undefined;
    const text = try formatInstruction(&buffer, &chunk, 0);
    try std.testing.expect(std.mem.indexOf(u8, text, "constant") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "3:5") != null);
}
