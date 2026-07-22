const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");

pub const StatementLowering = struct {
    pub fn emitRangeLoop(chunk: *bytecode.Chunk, start: i64, end: i64, step: i64) !void {
        // Emit specialized fast range unrolling setup
        try chunk.emit(.{ .op = .constant, .operand = start });
        try chunk.emit(.{ .op = .constant, .operand = end });
        try chunk.emit(.{ .op = .constant, .operand = step });
    }
};
