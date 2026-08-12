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

pub const FunctionCaptureInfo = struct {
    statement: usize,
    captures: [64][]const u8 = undefined,
    capture_count: usize = 0,
};

pub const State = struct {
    lambdas: []const LambdaInfo = &.{},
    function_count: usize = 0,
    active_captures: []const []const u8 = &.{},
    function_statements: []const usize = &.{},
    function_captures: []const FunctionCaptureInfo = &.{},
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

pub fn collectFunctionCaptures(allocator: std.mem.Allocator, module: *const ast.Module, statements: []const usize, captures: *std.ArrayListUnmanaged(FunctionCaptureInfo)) !void {
    for (statements) |statement_index| {
        const function = module.statements.items[statement_index].kind.function;
        var info = FunctionCaptureInfo{ .statement = statement_index };
        const parameters = module.parameters.items[function.params_first .. function.params_first + function.params_count];
        var index = function.body_first;
        while (index < function.body_first + function.body_count) : (index += 1) {
            switch (module.statements.items[index].kind) {
                .expression => |expression| try collectFunctionExpressionCaptures(module, expression, parameters, &info),
                .return_stmt => |expression| if (expression) |value| try collectFunctionExpressionCaptures(module, value, parameters, &info),
                .raise_stmt => |expression| if (expression) |value| try collectFunctionExpressionCaptures(module, value, parameters, &info),
                .control => |control| if (control.condition) |condition| try collectFunctionExpressionCaptures(module, condition, parameters, &info),
                .try_stmt => |try_stmt| if (try_stmt.except_match) |match| try collectFunctionExpressionCaptures(module, match, parameters, &info),
                .function => |nested| index = nested.body_first + nested.body_count,
                .class_decl => |nested| index = nested.body_first + nested.body_count,
                else => {},
            }
        }
        var write_index: usize = 0;
        for (info.captures[0..info.capture_count]) |capture| {
            var declared = std.mem.eql(u8, capture, "mudrisu") or std.mem.eql(u8, capture, "print") or std.mem.eql(u8, capture, "vidha") or std.mem.eql(u8, capture, "type") or std.mem.eql(u8, capture, "tanna") or std.mem.eql(u8, capture, "add") or std.mem.eql(u8, capture, "sub") or std.mem.eql(u8, capture, "mul") or std.mem.eql(u8, capture, "div") or std.mem.eql(u8, capture, "mod");
            for (module.statements.items) |candidate| if (candidate.kind == .function and std.mem.eql(u8, candidate.kind.function.name, capture)) {
                declared = true;
                break;
            };
            if (!declared) {
                info.captures[write_index] = capture;
                write_index += 1;
            }
        }
        info.capture_count = write_index;
        try captures.append(allocator, info);
    }
}

fn collectFunctionExpressionCaptures(module: *const ast.Module, expression: ast.ExprId, parameters: []const ast.Parameter, info: *FunctionCaptureInfo) error{ InvalidExpression, InvalidFunction }!void {
    var lambda_info = LambdaInfo{ .expression = expression, .params_first = 0, .params_count = 0, .body = expression, .capture_count = info.capture_count };
    @memcpy(lambda_info.captures[0..info.capture_count], info.captures[0..info.capture_count]);
    try collectLambdaCaptures(module, expression, parameters, &lambda_info);
    info.capture_count = lambda_info.capture_count;
    @memcpy(info.captures[0..info.capture_count], lambda_info.captures[0..info.capture_count]);
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
            if (value.first_arg > module.call_args.items.len or value.arg_count > module.call_args.items.len - value.first_arg) return error.InvalidExpression;
            for (module.call_args.items[value.first_arg .. value.first_arg + value.arg_count]) |argument_id| try collectLambdaCaptures(module, argument_id, parameters, info);
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
