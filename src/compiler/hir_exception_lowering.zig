const std = @import("std");
const ast = @import("ravi_ast");
const hir = @import("ravi_hir");
const expressions = @import("ravi_hir_expr_lowering");
const exceptionLocalName = "__ravi_exception";
const finallyResultName = "__ravi_finally_result";

pub fn lowerTry(allocator: std.mem.Allocator, source: *hir.Function, module: *const ast.Module, statement: anytype, names: []const []const u8, locals: []const []const u8, captures: []const []const u8) !void {
    if (statement.except_count == 0 and statement.finally_count == 1) return lowerTryFinally(allocator, source, module, statement, names, locals, captures);
    if (statement.body_count == 0 or statement.except_count == 0) return error.UnsupportedExpression;
    try source.appendEffect(.{ .try_begin = @enumFromInt(1) }, module.statements.items[statement.body_first].span.line);
    try lowerAssignments(allocator, source, module, statement.body_first, statement.body_count -| 1, names, locals, captures);
    const body = module.statements.items[statement.body_first + statement.body_count - 1];
    switch (body.kind) {
        .raise_stmt => |value| try source.appendEffect(.{ .raise_value = if (value) |id| try expressions.lowerWithLocals(allocator, source, module, id, names, locals, captures) else null }, body.span.line),
        .return_stmt => |value| {
            const id = value orelse return error.UnsupportedExpression;
            const lowered = try expressions.lowerWithLocals(allocator, source, module, id, names, locals, captures);
            try source.appendEffect(.try_end, body.span.line);
            try source.appendEffect(.{ .return_value = lowered }, body.span.line);
        },
        else => return error.UnsupportedExpression,
    }
    const handler = module.statements.items[statement.except_first + statement.except_count - 1];
    const exception_slot = if (statement.except_binding) |binding| expressions.localIndex(locals, binding) orelse return error.InvalidExpression else if (statement.except_match != null) expressions.localIndex(locals, exceptionLocalName) orelse return error.InvalidExpression else null;
    const handler_start = source.instructions.items.len;
    if (exception_slot) |slot| try source.appendEffect(.{ .bind_exception = slot }, handler.span.line);
    if (statement.except_match) |match| {
        const exception = try source.appendValue(.dynamic, .{ .load_local = exception_slot.? }, handler.span.line);
        const expected = try expressions.lowerWithLocals(allocator, source, module, match, names, locals, captures);
        const matched = try source.appendValue(.boolean, .{ .binary = .{ .operator = .equal, .left = exception, .right = expected } }, handler.span.line);
        try source.appendEffect(.{ .branch = .{ .condition = matched, .then_block = @enumFromInt(2), .else_block = @enumFromInt(3) } }, handler.span.line);
    }
    const success_start = source.instructions.items.len;
    try lowerAssignments(allocator, source, module, statement.except_first, statement.except_count -| 1, names, locals, captures);
    const handler_value = switch (handler.kind) {
        .return_stmt => |value| value orelse return error.UnsupportedExpression,
        else => return error.UnsupportedExpression,
    };
    const handler_result = try expressions.lowerWithLocals(allocator, source, module, handler_value, names, locals, captures);
    try source.appendEffect(.{ .return_value = handler_result }, handler.span.line);
    const failure_start = source.instructions.items.len;
    if (statement.except_match != null) try source.appendEffect(.{ .raise_value = null }, handler.span.line);
    if (statement.except_match != null) {
        try source.setBlocks(&.{ .{ .first_instruction = 0, .instruction_count = handler_start }, .{ .first_instruction = handler_start, .instruction_count = success_start - handler_start }, .{ .first_instruction = success_start, .instruction_count = failure_start - success_start }, .{ .first_instruction = failure_start, .instruction_count = source.instructions.items.len - failure_start } });
    } else try source.setBlocks(&.{ .{ .first_instruction = 0, .instruction_count = handler_start }, .{ .first_instruction = handler_start, .instruction_count = source.instructions.items.len - handler_start } });
}

fn lowerAssignments(allocator: std.mem.Allocator, source: *hir.Function, module: *const ast.Module, first: usize, count: usize, names: []const []const u8, locals: []const []const u8, captures: []const []const u8) !void {
    const end = std.math.add(usize, first, count) catch return error.InvalidExpression;
    if (end > module.statements.items.len) return error.InvalidExpression;
    for (module.statements.items[first..end]) |statement| {
        const id = switch (statement.kind) {
            .expression => |value| value,
            else => return error.UnsupportedExpression,
        };
        const assignment = switch (module.expressions.items[@as(usize, id)].kind) {
            .assignment => |value| value,
            else => return error.UnsupportedExpression,
        };
        if (assignment.target != null) return error.UnsupportedExpression;
        const value = try expressions.lowerWithLocals(allocator, source, module, assignment.value, names, locals, captures);
        if (expressions.localIndex(captures, assignment.name)) |slot| try source.appendEffect(.{ .store_capture = .{ .slot = slot, .value = value } }, statement.span.line) else try source.appendEffect(.{ .store_local = .{ .slot = expressions.localIndex(locals, assignment.name) orelse return error.InvalidExpression, .value = value } }, statement.span.line);
    }
}

fn lowerTryFinally(allocator: std.mem.Allocator, source: *hir.Function, module: *const ast.Module, statement: anytype, names: []const []const u8, locals: []const []const u8, captures: []const []const u8) !void {
    const body = module.statements.items[statement.body_first];
    const finalizer = module.statements.items[statement.finally_first];
    const assignment = switch (finalizer.kind) {
        .expression => |id| switch (module.expressions.items[@as(usize, id)].kind) {
            .assignment => |value| value,
            else => return error.UnsupportedExpression,
        },
        else => return error.UnsupportedExpression,
    };
    const result_slot = expressions.localIndex(locals, finallyResultName) orelse return error.InvalidExpression;
    const cleanup_slot = expressions.localIndex(locals, assignment.name) orelse return error.InvalidExpression;
    try source.appendEffect(.{ .try_begin = @enumFromInt(1) }, body.span.line);
    const body_value = switch (body.kind) {
        .return_stmt => |value| value orelse return error.UnsupportedExpression,
        else => return error.UnsupportedExpression,
    };
    const result = try expressions.lowerWithLocals(allocator, source, module, body_value, names, locals, captures);
    try source.appendEffect(.{ .store_local = .{ .slot = result_slot, .value = result } }, body.span.line);
    try source.appendEffect(.try_end, body.span.line);
    const cleanup_value = try expressions.lowerWithLocals(allocator, source, module, assignment.value, names, locals, captures);
    try source.appendEffect(.{ .store_local = .{ .slot = cleanup_slot, .value = cleanup_value } }, finalizer.span.line);
    const returned = try source.appendValue(.dynamic, .{ .load_local = result_slot }, body.span.line);
    try source.appendEffect(.{ .return_value = returned }, body.span.line);
    const handler_cleanup = try expressions.lowerWithLocals(allocator, source, module, assignment.value, names, locals, captures);
    try source.appendEffect(.{ .store_local = .{ .slot = cleanup_slot, .value = handler_cleanup } }, finalizer.span.line);
    try source.appendEffect(.{ .raise_value = null }, finalizer.span.line);
    const handler_start = source.instructions.items.len - 3;
    try source.setBlocks(&.{ .{ .first_instruction = 0, .instruction_count = handler_start }, .{ .first_instruction = handler_start, .instruction_count = 3 } });
}
