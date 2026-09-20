const std = @import("std");
const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");

pub fn lower(comptime Error: type, compiler: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, first: usize, count: usize, opcode: bytecode.OpCode, names: anytype, expression: anytype) Error!void {
    const elements = if (opcode == .make_dict) std.math.mul(usize, count, 2) catch return error.InvalidExpression else count;
    if (first > module.collection_items.items.len or elements > module.collection_items.items.len - first) return error.InvalidExpression;
    for (module.collection_items.items[first .. first + elements]) |id| try expression(Error, compiler, chunk, module, id, names);
    try chunk.emit(.{ .op = opcode, .operand = @intCast(count) });
}
