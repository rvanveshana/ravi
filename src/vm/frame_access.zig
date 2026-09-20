const object_storage = @import("object_storage.zig");
const state_helpers = @import("state_helpers.zig");

pub fn loadLocal(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(self.frames[self.frame_top].locals.len))) return error.InvalidLocal;
    const value = self.frames[self.frame_top].locals[@intCast(operand)];
    try state_helpers.push(self, if (value.handleKind() == .cell) self.cells[value.handleIndex().?].value else value);
}

pub fn loadLocalRef(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(self.frames[self.frame_top].locals.len))) return error.InvalidLocal;
    const local = &self.frames[self.frame_top].locals[@intCast(operand)];
    if (local.handleKind() != .cell) {
        const cell = try object_storage.newCell(self, local.*);
        local.* = try @import("value_runtime.zig").makeHandle(.cell, cell);
    }
    try state_helpers.push(self, local.*);
}

pub fn storeLocal(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0 or self.stack_top == 0) return error.InvalidLocal;
    try self.frames[self.frame_top].ensureLocals(self.allocator, @as(usize, @intCast(operand)) + 1);
    const local = &self.frames[self.frame_top].locals[@intCast(operand)];
    const value = self.stack[self.stack_top - 1];
    if (local.handleKind() == .cell) {
        self.cells[local.handleIndex().?].value = value;
        try object_storage.writeBarrierValue(self, local.*, value);
    } else local.* = value;
}

pub fn loadCapture(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(self.frames[self.frame_top].captures.len))) return error.InvalidLocal;
    const captured = self.frames[self.frame_top].captures[@intCast(operand)];
    if (captured.handleKind() == .cell) {
        const cell = captured.handleIndex().?;
        if (cell >= self.cell_count) return error.InvalidLocal;
        try state_helpers.push(self, self.cells[cell].value);
    } else try state_helpers.push(self, captured);
}

pub fn loadCaptureRef(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(self.frames[self.frame_top].captures.len))) return error.InvalidLocal;
    try state_helpers.push(self, self.frames[self.frame_top].captures[@intCast(operand)]);
}

pub fn storeCapture(comptime Error: type, self: anytype, operand: i64) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(self.frames[self.frame_top].captures.len)) or self.stack_top == 0) return error.InvalidLocal;
    const capture = self.frames[self.frame_top].captures[@intCast(operand)];
    if (capture.handleKind() != .cell) return error.InvalidLocal;
    const cell = capture.handleIndex().?;
    if (cell >= self.cell_count) return error.InvalidLocal;
    self.cells[cell].value = self.stack[self.stack_top - 1];
    try object_storage.writeBarrierValue(self, capture, self.stack[self.stack_top - 1]);
}
