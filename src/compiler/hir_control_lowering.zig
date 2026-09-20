const std = @import("std");
const ast = @import("ravi_ast");
const hir = @import("ravi_hir");
const expressions = @import("ravi_hir_expr_lowering");
pub fn lowerControl(allocator: std.mem.Allocator, source: *hir.Function, module: *const ast.Module, declaration: anytype, control: anytype, names: []const []const u8, locals: []const []const u8, captures: []const []const u8) !void {
    const condition = control.condition orelse return error.UnsupportedExpression;
    if (std.mem.eql(u8, control.keyword, "if") and control.body_count > 0 and control.else_count > 0) {
        const then_end = std.math.add(usize, control.body_first, control.body_count) catch return error.InvalidExpression;
        const else_end = std.math.add(usize, control.else_first, control.else_count) catch return error.InvalidExpression;
        if (then_end > module.statements.items.len or else_end > module.statements.items.len) return error.InvalidExpression;
        const condition_value = try expressions.lowerWithLocals(allocator, source, module, condition, names, locals, captures);
        try source.appendEffect(.{ .branch = .{ .condition = condition_value, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } }, module.expressions.items[condition].span.line);
        const then_start = source.instructions.items.len;
        try lowerBranchReturn(allocator, source, module, control.body_first, control.body_count, names, locals, captures);
        const then_count = source.instructions.items.len - then_start;
        const else_start = source.instructions.items.len;
        try lowerBranchReturn(allocator, source, module, control.else_first, control.else_count, names, locals, captures);
        const else_count = source.instructions.items.len - else_start;
        try source.setBlocks(&.{ .{ .first_instruction = 0, .instruction_count = then_start }, .{ .first_instruction = then_start, .instruction_count = then_count }, .{ .first_instruction = else_start, .instruction_count = else_count } });
        return;
    }
    if (std.mem.eql(u8, control.keyword, "while")) {
        const header = source.instructions.items.len;
        const value = try expressions.lowerWithLocals(allocator, source, module, condition, names, locals, captures);
        try source.appendEffect(.{ .branch = .{ .condition = value, .then_block = @enumFromInt(2), .else_block = @enumFromInt(3) } }, module.expressions.items[condition].span.line);
        const body_id = switch (module.statements.items[control.body_first].kind) {
            .expression => |id| id,
            else => return error.UnsupportedExpression,
        };
        const assignment = switch (module.expressions.items[body_id].kind) {
            .assignment => |assignment_value| assignment_value,
            else => return error.UnsupportedExpression,
        };
        const body_value = try expressions.lowerWithLocals(allocator, source, module, assignment.value, names, locals, captures);
        if (expressions.localIndex(captures, assignment.name)) |slot| {
            try source.appendEffect(.{ .store_capture = .{ .slot = slot, .value = body_value } }, module.expressions.items[body_id].span.line);
        } else {
            try source.appendEffect(.{ .store_local = .{ .slot = expressions.localIndex(locals, assignment.name) orelse return error.InvalidExpression, .value = body_value } }, module.expressions.items[body_id].span.line);
        }
        try source.appendEffect(.{ .jump = @enumFromInt(0) }, module.expressions.items[body_id].span.line);
        const return_id = switch (module.statements.items[declaration.body_first + declaration.body_count - 1].kind) {
            .return_stmt => |return_value| return_value orelse return error.UnsupportedExpression,
            else => return error.UnsupportedExpression,
        };
        try source.appendEffect(.{ .return_value = try expressions.lowerWithLocals(allocator, source, module, return_id, names, locals, captures) }, module.expressions.items[return_id].span.line);
        try source.setBlocks(&.{ .{ .first_instruction = 0, .instruction_count = header }, .{ .first_instruction = header, .instruction_count = 1 }, .{ .first_instruction = header + 1, .instruction_count = 3 }, .{ .first_instruction = source.instructions.items.len - 1, .instruction_count = 1 } });
        return;
    }
    const condition_value = try expressions.lowerWithLocals(allocator, source, module, condition, names, locals, captures);
    try source.appendEffect(.{ .branch = .{ .condition = condition_value, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } }, module.expressions.items[condition].span.line);
    const then_id = switch (module.statements.items[control.body_first].kind) {
        .return_stmt => |value| value orelse return error.UnsupportedExpression,
        else => return error.UnsupportedExpression,
    };
    const else_id = switch (module.statements.items[control.else_first].kind) {
        .return_stmt => |value| value orelse return error.UnsupportedExpression,
        else => return error.UnsupportedExpression,
    };
    try source.appendEffect(.{ .return_value = try expressions.lowerWithLocals(allocator, source, module, then_id, names, locals, captures) }, module.expressions.items[then_id].span.line);
    try source.appendEffect(.{ .return_value = try expressions.lowerWithLocals(allocator, source, module, else_id, names, locals, captures) }, module.expressions.items[else_id].span.line);
    try source.setBlocks(&.{ .{ .first_instruction = 0, .instruction_count = 1 }, .{ .first_instruction = 1, .instruction_count = 1 }, .{ .first_instruction = 2, .instruction_count = 1 } });
}

fn lowerBranchReturn(allocator: std.mem.Allocator, source: *hir.Function, module: *const ast.Module, first: usize, count: usize, names: []const []const u8, locals: []const []const u8, captures: []const []const u8) !void {
    if (count == 0) return error.UnsupportedExpression;
    const end = std.math.add(usize, first, count) catch return error.InvalidExpression;
    if (end > module.statements.items.len) return error.InvalidExpression;
    for (module.statements.items[first .. end - 1]) |statement| {
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
        if (expressions.localIndex(captures, assignment.name)) |slot| {
            try source.appendEffect(.{ .store_capture = .{ .slot = slot, .value = value } }, statement.span.line);
        } else {
            try source.appendEffect(.{ .store_local = .{ .slot = expressions.localIndex(locals, assignment.name) orelse return error.InvalidExpression, .value = value } }, statement.span.line);
        }
    }
    const terminal = module.statements.items[end - 1];
    const value = switch (terminal.kind) {
        .return_stmt => |id| id orelse return error.UnsupportedExpression,
        else => return error.UnsupportedExpression,
    };
    try source.appendEffect(.{ .return_value = try expressions.lowerWithLocals(allocator, source, module, value, names, locals, captures) }, terminal.span.line);
}
