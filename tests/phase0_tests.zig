const std = @import("std");
const bytecode = @import("ravi_bytecode");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");

fn makeChunk(allocator: std.mem.Allocator) !void {
    var chunk = bytecode.Chunk.init(allocator);
    defer chunk.deinit();
    _ = try chunk.addString("phase0");
    _ = try chunk.addFloat(3.25);
    _ = try chunk.addFormat("{value}", 1);
    _ = try chunk.addFunction(.{ .entry = 1, .arity = 0, .name = "main" });
    try chunk.addCapture(.{ .function = 0, .slot = 0 });
    try chunk.emit(.{ .op = .constant, .operand = 0 });
    try chunk.emit(.{ .op = .return_value });
}

fn lexAndParse(allocator: std.mem.Allocator, source: []const u8) !void {
    var scan = try lexer.Lexer.init(allocator, source);
    defer scan.deinit();
    const tokens = scan.tokenize() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    var instance = parser.Parser.init(allocator, tokens);
    var module = instance.parseRecovering() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return,
    };
    module.deinit();
}

test "bytecode construction cleans up at every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, makeChunk, .{});
}

test "lexer and parser clean up at every allocation failure" {
    const source = "kriya add(value: int):\n    kodu value + 1\n\nadd(2)\n";
    try std.testing.checkAllAllocationFailures(std.testing.allocator, lexAndParse, .{source});
}

test "lexer parser fuzz entry point accepts arbitrary UTF-8 bytes" {
    var state: u64 = 0x726176695f66757a;
    for (0..512) |_| {
        var source: [96]u8 = undefined;
        for (&source) |*byte| {
            state = state *% 6364136223846793005 +% 1442695040888963407;
            byte.* = @truncate(state >> 56);
        }
        try lexAndParse(std.testing.allocator, &source);
    }
}

test "verifier rejects invalid locals captures constants and metadata" {
    var locals = bytecode.Chunk.init(std.testing.allocator);
    defer locals.deinit();
    try locals.emit(.{ .op = .load_local, .operand = -1 });
    try std.testing.expectError(error.InvalidLocal, locals.verify());

    var captures = bytecode.Chunk.init(std.testing.allocator);
    defer captures.deinit();
    try captures.emit(.{ .op = .make_closure, .operand = 0 });
    try std.testing.expectError(error.InvalidInstruction, captures.verify());

    var constants = bytecode.Chunk.init(std.testing.allocator);
    defer constants.deinit();
    try constants.emit(.{ .op = .make_string, .operand = 0 });
    try std.testing.expectError(error.InvalidInstruction, constants.verify());

    var source_map = bytecode.Chunk.init(std.testing.allocator);
    defer source_map.deinit();
    try source_map.emit(.{ .op = .halt });
    _ = source_map.source_map.pop();
    try std.testing.expectError(error.InvalidInstruction, source_map.verify());

    var root_map = bytecode.Chunk.init(std.testing.allocator);
    defer root_map.deinit();
    try root_map.emit(.{ .op = .halt });
    _ = root_map.root_map.pop();
    try std.testing.expectError(error.InvalidInstruction, root_map.verify());
}

test "verifier rejects invalid handler and jump targets" {
    var handler = bytecode.Chunk.init(std.testing.allocator);
    defer handler.deinit();
    try handler.emit(.{ .op = .try_begin, .operand = 99 });
    try handler.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidJump, handler.verify());

    var jump = bytecode.Chunk.init(std.testing.allocator);
    defer jump.deinit();
    try jump.emit(.{ .op = .jump, .operand = -1 });
    try jump.emit(.{ .op = .halt });
    try std.testing.expectError(error.InvalidJump, jump.verify());
}
