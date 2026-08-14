const std = @import("std");
const ast = @import("ravi_ast");

pub fn collectControlLocals(module: *const ast.Module, first: usize, count: usize, locals: *std.ArrayListUnmanaged([]const u8), parameters: []const ast.Parameter) void {
    if (count == 0 or first >= module.statements.items.len) return;
    const end = @min(first +| count, module.statements.items.len);
    for (module.statements.items[first..end]) |statement| switch (statement.kind) {
        .control => |control| {
            collectRangeLocals(module, control.body_first, control.body_count, locals, parameters);
            collectRangeLocals(module, control.else_first, control.else_count, locals, parameters);
        },
        .try_stmt => |try_statement| {
            collectRangeLocals(module, try_statement.body_first, try_statement.body_count, locals, parameters);
            collectRangeLocals(module, try_statement.except_first, try_statement.except_count, locals, parameters);
            collectRangeLocals(module, try_statement.finally_first, try_statement.finally_count, locals, parameters);
        },
        else => {},
    };
}

fn collectRangeLocals(module: *const ast.Module, first: usize, count: usize, locals: *std.ArrayListUnmanaged([]const u8), parameters: []const ast.Parameter) void {
    if (count == 0 or first >= module.statements.items.len) return;
    const end = @min(first +| count, module.statements.items.len);
    for (module.statements.items[first..end]) |statement| switch (statement.kind) {
        .expression => |id| switch (module.expressions.items[@as(usize, id)].kind) {
            .assignment => |assignment| if (assignment.target == null and !isParameter(parameters, assignment.name) and !contains(locals.items, assignment.name)) locals.append(module.allocator, assignment.name) catch {},
            else => {},
        },
        else => {},
    };
}

fn isParameter(parameters: []const ast.Parameter, name: []const u8) bool {
    for (parameters) |parameter| if (std.mem.eql(u8, parameter.name, name)) return true;
    return false;
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}
