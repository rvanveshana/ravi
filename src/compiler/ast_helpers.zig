const std = @import("std");
const ast = @import("ravi_ast");

pub const LoopContext = struct { continue_target: usize, breaks_first: usize, continues_first: usize = 0 };
pub const FinallyContext = struct { first: usize, count: usize };
pub const LambdaInfo = struct {
    expression: ast.ExprId,
    params_first: usize,
    params_count: usize,
    body: ast.ExprId,
    captures: [64][]const u8 = undefined,
    capture_count: usize = 0,
};

pub const State = struct {
    lambdas: []const LambdaInfo = &.{},
    function_count: usize = 0,
    active_captures: []const []const u8 = &.{},
    function_statements: []const usize = &.{},
    continue_targets: ?*std.ArrayListUnmanaged(usize) = null,
    finalizers: ?*std.ArrayListUnmanaged(FinallyContext) = null,
    finalizer_limit: ?usize = null,
};

pub fn collectLambdaInfos(allocator: std.mem.Allocator, module: *const ast.Module, lambdas: *std.ArrayListUnmanaged(LambdaInfo)) !void {
    for (module.expressions.items, 0..) |expression, expression_id| switch (expression.kind) {
        .lambda => |lambda| {
            var info = LambdaInfo{ .expression = @intCast(expression_id), .params_first = lambda.params_first, .params_count = lambda.params_count, .body = lambda.body };
            try collectLambdaCaptures(module, lambda.body, module.parameters.items[lambda.params_first .. lambda.params_first + lambda.params_count], &info);
            try lambdas.append(allocator, info);
        },
        else => {},
    };
}

pub fn collectFunctionStatements(allocator: std.mem.Allocator, module: *const ast.Module, statements: *std.ArrayListUnmanaged(usize)) !void {
    for (module.statements.items, 0..) |statement, index| switch (statement.kind) {
        .function => |function| {
            try statements.append(allocator, index);
            _ = function;
        },
        else => {},
    };
}

pub fn collectLambdaCaptures(module: *const ast.Module, expression_id: ast.ExprId, parameters: []const ast.Parameter, info: *LambdaInfo) error{ InvalidExpression, InvalidFunction }!void {
    if (@as(usize, expression_id) >= module.expressions.items.len) return error.InvalidExpression;
    switch (module.expressions.items[expression_id].kind) {
        .name => |name| {
            for (parameters) |parameter| if (std.mem.eql(u8, parameter.name, name)) return;
            for (info.captures[0..info.capture_count]) |capture| if (std.mem.eql(u8, capture, name)) return;
            if (info.capture_count == info.captures.len) return error.InvalidFunction;
            info.captures[info.capture_count] = name;
            info.capture_count += 1;
        },
        .member => |value| try collectLambdaCaptures(module, value.object, parameters, info),
        .unary => |value| try collectLambdaCaptures(module, value.operand, parameters, info),
        .binary => |value| {
            try collectLambdaCaptures(module, value.left, parameters, info);
            try collectLambdaCaptures(module, value.right, parameters, info);
        },
        .call => |value| {
            try collectLambdaCaptures(module, value.callee, parameters, info);
            if (value.first_arg > module.expressions.items.len or value.arg_count > module.expressions.items.len - value.first_arg) return error.InvalidExpression;
            for (value.first_arg..value.first_arg + value.arg_count) |argument_id| try collectLambdaCaptures(module, @intCast(argument_id), parameters, info);
        },
        .assignment => |value| try collectLambdaCaptures(module, value.value, parameters, info),
        .array => |value| for (value.first..value.first + value.count) |element_id| try collectLambdaCaptures(module, @intCast(element_id), parameters, info),
        .tuple => |value| for (value.first..value.first + value.count) |element_id| try collectLambdaCaptures(module, @intCast(element_id), parameters, info),
        .set => |value| for (value.first..value.first + value.count) |element_id| try collectLambdaCaptures(module, @intCast(element_id), parameters, info),
        .map => |value| for (value.first..value.first + value.count) |element_id| try collectLambdaCaptures(module, @intCast(element_id), parameters, info),
        .index => |value| {
            try collectLambdaCaptures(module, value.object, parameters, info);
            try collectLambdaCaptures(module, value.index, parameters, info);
        },
        .slice => |value| {
            if (value.start) |start| try collectLambdaCaptures(module, start, parameters, info);
            if (value.end) |end| try collectLambdaCaptures(module, end, parameters, info);
            try collectLambdaCaptures(module, value.object, parameters, info);
        },
        .lambda => |value| try collectLambdaCaptures(module, value.body, parameters, info),
        else => {},
    }
}
