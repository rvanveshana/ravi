const std = @import("std");
const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");

fn comparison(op: ast.BinaryOp) bool {
    return switch (op) {
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => true,
        else => false,
    };
}
fn opcode(op: ast.BinaryOp) !bytecode.OpCode {
    return switch (op) {
        .add => .add,
        .subtract => .subtract,
        .multiply => .multiply,
        .divide => .divide,
        .modulo => .modulo,
        .equal, .is => .equal,
        .not_equal => .not_equal,
        .less => .less,
        .less_equal => .less_equal,
        .greater => .greater,
        .greater_equal => .greater_equal,
        else => error.UnsupportedOperator,
    };
}
pub fn lower(comptime Error: type, compiler: anytype, chunk: *bytecode.Chunk, module: *const ast.Module, binary: anytype, names: anytype, expression: anytype) Error!void {
    if (binary.op == .in_op) {
        try expression(Error, compiler, chunk, module, binary.right, names);
        try expression(Error, compiler, chunk, module, binary.left, names);
        try chunk.emit(.{ .op = .contains_collection });
        return;
    }
    if (binary.op == .logic_and or binary.op == .logic_or) {
        try expression(Error, compiler, chunk, module, binary.left, names);
        try chunk.emit(.{ .op = .dup });
        if (binary.op == .logic_or) try chunk.emit(.{ .op = .not });
        const finish = chunk.code.items.len;
        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
        try chunk.emit(.{ .op = .pop });
        try expression(Error, compiler, chunk, module, binary.right, names);
        chunk.code.items[finish].operand = @intCast(chunk.code.items.len);
        return;
    }
    if (comparison(binary.op)) {
        var operands: std.ArrayListUnmanaged(ast.ExprId) = .empty;
        var operators: std.ArrayListUnmanaged(ast.BinaryOp) = .empty;
        defer operands.deinit(compiler.allocator);
        defer operators.deinit(compiler.allocator);
        try flatten(compiler.allocator, module, binary.left, &operands, &operators);
        try operators.append(compiler.allocator, binary.op);
        try operands.append(compiler.allocator, binary.right);
        var exits: std.ArrayListUnmanaged(usize) = .empty;
        defer exits.deinit(compiler.allocator);
        try expression(Error, compiler, chunk, module, operands.items[0], names);
        for (operators.items, 0..) |operator, index| {
            try expression(Error, compiler, chunk, module, operands.items[index + 1], names);
            const more = index + 1 < operators.items.len;
            const slot = names.items.len;
            if (more) {
                try names.append(compiler.allocator, "");
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
            }
            try chunk.emit(.{ .op = try opcode(operator) });
            if (more) {
                try chunk.emit(.{ .op = .dup });
                try exits.append(compiler.allocator, chunk.code.items.len);
                try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                try chunk.emit(.{ .op = .pop });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
            }
        }
        for (exits.items) |jump| chunk.code.items[jump].operand = @intCast(chunk.code.items.len);
        return;
    }
    try expression(Error, compiler, chunk, module, binary.left, names);
    try expression(Error, compiler, chunk, module, binary.right, names);
    try chunk.emit(.{ .op = try opcode(binary.op) });
}
fn flatten(allocator: std.mem.Allocator, module: *const ast.Module, id: ast.ExprId, operands: *std.ArrayListUnmanaged(ast.ExprId), operators: *std.ArrayListUnmanaged(ast.BinaryOp)) !void {
    const value = module.expressions.items[id];
    if (!value.parenthesized and value.kind == .binary and comparison(value.kind.binary.op)) {
        try flatten(allocator, module, value.kind.binary.left, operands, operators);
        try operators.append(allocator, value.kind.binary.op);
        try operands.append(allocator, value.kind.binary.right);
    } else try operands.append(allocator, id);
}
