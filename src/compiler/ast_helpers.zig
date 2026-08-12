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

/// Fixed-capacity set of names visible from a lexical scope, used to tell a
/// genuinely new local variable apart from an intended capture of an
/// enclosing variable when both are merely "assigned, then read" locally.
const NameSet = struct {
    items: [128][]const u8 = undefined,
    count: usize = 0,

    fn contains(self: *const NameSet, name: []const u8) bool {
        for (self.items[0..self.count]) |existing| if (std.mem.eql(u8, existing, name)) return true;
        return false;
    }

    fn add(self: *NameSet, name: []const u8) void {
        if (self.contains(name) or self.count >= self.items.len) return;
        self.items[self.count] = name;
        self.count += 1;
    }

    fn addAll(self: *NameSet, other: *const NameSet) void {
        for (other.items[0..other.count]) |name| self.add(name);
    }

    fn addParameters(self: *NameSet, parameters: []const ast.Parameter) void {
        for (parameters) |parameter| self.add(parameter.name);
    }
};

/// Collect names directly declared in a statement range (simple assignment
/// targets, loop targets, except and context bindings), without descending
/// into nested function or class scopes, which introduce their own scope.
///
/// This parser appends a function/class body to the flat statement list
/// *before* appending the function/class statement itself, so a nested
/// scope's body physically precedes its own declaring statement. Nested
/// ranges are therefore identified in a first pass and skipped in the main
/// scan, rather than reactively jumped over when the declaring statement is
/// reached (which is already past the end of the range).
fn collectDeclaredNames(module: *const ast.Module, first: usize, count: usize, out: *NameSet) void {
    var skip_ranges: [64][2]usize = undefined;
    var skip_count: usize = 0;
    {
        var index = first;
        while (index < first + count and index < module.statements.items.len) : (index += 1) {
            switch (module.statements.items[index].kind) {
                .function => |nested| if (skip_count < skip_ranges.len) {
                    skip_ranges[skip_count] = .{ nested.body_first, nested.body_first + nested.body_count };
                    skip_count += 1;
                },
                .class_decl => |nested| if (skip_count < skip_ranges.len) {
                    skip_ranges[skip_count] = .{ nested.body_first, nested.body_first + nested.body_count };
                    skip_count += 1;
                },
                else => {},
            }
        }
    }

    var index = first;
    while (index < first + count and index < module.statements.items.len) : (index += 1) {
        var skip_to: ?usize = null;
        for (skip_ranges[0..skip_count]) |range| if (index >= range[0] and index < range[1]) {
            skip_to = range[1];
            break;
        };
        if (skip_to) |target| {
            if (target == 0) continue;
            index = target - 1;
            continue;
        }
        switch (module.statements.items[index].kind) {
            .expression => |expression_id| {
                if (@as(usize, expression_id) < module.expressions.items.len) {
                    switch (module.expressions.items[expression_id].kind) {
                        .assignment => |assignment| if (assignment.target == null) out.add(assignment.name),
                        else => {},
                    }
                }
            },
            .control => |control| {
                if (control.target) |target| out.add(target);
                collectDeclaredNames(module, control.body_first, control.body_count, out);
                if (control.else_count != 0) collectDeclaredNames(module, control.else_first, control.else_count, out);
            },
            .try_stmt => |try_stmt| {
                if (try_stmt.except_binding) |binding| out.add(binding);
                collectDeclaredNames(module, try_stmt.body_first, try_stmt.body_count, out);
                if (try_stmt.except_count != 0) collectDeclaredNames(module, try_stmt.except_first, try_stmt.except_count, out);
                if (try_stmt.finally_count != 0) collectDeclaredNames(module, try_stmt.finally_first, try_stmt.finally_count, out);
            },
            .context => |context| {
                if (context.binding) |binding| out.add(binding);
                collectDeclaredNames(module, context.body_first, context.body_count, out);
            },
            else => {},
        }
    }
}

pub fn collectFunctionCaptures(allocator: std.mem.Allocator, module: *const ast.Module, statements: []const usize, captures: *std.ArrayListUnmanaged(FunctionCaptureInfo)) !void {
    var top_level_scope = NameSet{};
    collectDeclaredNames(module, 0, module.statements.items.len, &top_level_scope);
    for (module.statements.items) |statement| if (statement.kind == .function) top_level_scope.add(statement.kind.function.name);

    const StackEntry = struct { end: usize, visible: NameSet };
    var scope_stack: std.ArrayListUnmanaged(StackEntry) = .empty;
    defer scope_stack.deinit(allocator);

    for (statements) |statement_index| {
        const function = module.statements.items[statement_index].kind.function;
        while (scope_stack.items.len > 0 and statement_index >= scope_stack.items[scope_stack.items.len - 1].end) _ = scope_stack.pop();
        const parent_visible: NameSet = if (scope_stack.items.len > 0) scope_stack.items[scope_stack.items.len - 1].visible else top_level_scope;

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
            var exclude = std.mem.eql(u8, capture, "mudrisu") or std.mem.eql(u8, capture, "print") or std.mem.eql(u8, capture, "vidha") or std.mem.eql(u8, capture, "type") or std.mem.eql(u8, capture, "tanna") or std.mem.eql(u8, capture, "add") or std.mem.eql(u8, capture, "sub") or std.mem.eql(u8, capture, "mul") or std.mem.eql(u8, capture, "div") or std.mem.eql(u8, capture, "mod");
            for (module.statements.items) |candidate| if (candidate.kind == .function and std.mem.eql(u8, candidate.kind.function.name, capture)) {
                exclude = true;
                break;
            };
            // A name only needs to be captured when it is actually visible in
            // an enclosing scope; otherwise it is a fresh local of this function.
            if (!exclude and !parent_visible.contains(capture)) exclude = true;
            if (!exclude) {
                info.captures[write_index] = capture;
                write_index += 1;
            }
        }
        info.capture_count = write_index;
        try captures.append(allocator, info);

        var own_visible = parent_visible;
        own_visible.addParameters(parameters);
        collectDeclaredNames(module, function.body_first, function.body_count, &own_visible);
        try scope_stack.append(allocator, .{ .end = function.body_first + function.body_count, .visible = own_visible });
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
