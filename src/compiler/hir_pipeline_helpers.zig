const std = @import("std");
const ast = @import("ravi_ast");

pub fn functionIndex(module: *const ast.Module, name: []const u8) ?usize {
    var index: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| {
            if (std.mem.eql(u8, function.name, name)) return index;
            index += 1;
        },
        else => {},
    };
    return null;
}

pub fn functionArity(module: *const ast.Module, name: []const u8) ?usize {
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| if (std.mem.eql(u8, function.name, name)) return function.params_count,
        else => {},
    };
    return null;
}

pub fn parameterIndex(parameters: []const ast.Parameter, name: []const u8) ?usize {
    for (parameters, 0..) |parameter, index| if (std.mem.eql(u8, parameter.name, name)) return index;
    return null;
}

pub fn binarySupported(operator: ast.BinaryOp) bool {
    return switch (operator) {
        .add, .subtract, .multiply, .divide, .modulo, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => true,
        else => false,
    };
}

pub fn isPrintName(name: []const u8) bool {
    return std.mem.eql(u8, name, "mudrisu") or std.mem.eql(u8, name, "print");
}
