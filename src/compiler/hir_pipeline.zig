const std = @import("std");
const ast = @import("ravi_ast");
const hir = @import("ravi_hir");
const mir = @import("ravi_mir");
const lowering = @import("ravi_hir_lowering");
const mir_bytecode = @import("ravi_mir_bytecode");
const bytecode = @import("ravi_bytecode");
const compatibility = @import("ravi_hir_compatibility");
const ast_helpers = @import("ravi_ast_helpers");
const pipeline_helpers = @import("ravi_hir_pipeline_helpers");
const pipeline_support = @import("ravi_hir_pipeline_support");
pub const Error = std.mem.Allocator.Error || error{ UnsupportedExpression, InvalidExpression, InvalidFunction, InvalidParameter };
pub fn supports(module: *const ast.Module) bool {
    var body_indices = std.AutoHashMap(usize, void).init(module.allocator);
    defer body_indices.deinit();
    var function_statements: std.ArrayListUnmanaged(usize) = .empty;
    defer function_statements.deinit(module.allocator);
    for (module.statements.items, 0..) |statement, index| if (statement.kind == .function) function_statements.append(module.allocator, index) catch return false;
    var function_captures: std.ArrayListUnmanaged(ast_helpers.FunctionCaptureInfo) = .empty;
    defer function_captures.deinit(module.allocator);
    ast_helpers.collectFunctionCaptures(module.allocator, module, function_statements.items, &function_captures) catch return false;
    var function_index: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| {
            if (function.body_first > module.statements.items.len or function.body_count > module.statements.items.len - function.body_first) return false;
            if (function.params_first > module.parameters.items.len or function.params_count > module.parameters.items.len - function.params_first) return false;
            for (function.body_first..function.body_first + function.body_count) |index| body_indices.put(index, {}) catch return false;
            const captures = function_captures.items[function_index].captures[0..function_captures.items[function_index].capture_count];
            if (!functionBodySupported(module, function.body_first, function.body_count, function.params_first, function.params_count, captures)) return false;
            function_index += 1;
        },
        else => {},
    };
    var expression_count: usize = 0;
    var top_level_locals: std.ArrayListUnmanaged([]const u8) = .empty;
    defer top_level_locals.deinit(module.allocator);
    for (module.statements.items, 0..) |statement, index| {
        if (body_indices.contains(index)) continue;
        switch (statement.kind) {
            .import, .function, .class_decl => {},
            .expression => |id| {
                expression_count += 1;
                switch (module.expressions.items[@as(usize, id)].kind) {
                    .assignment => |assignment| {
                        if (assignment.target) |target| {
                            if (module.expressions.items[@as(usize, target)].kind != .index or !expressionSupportedWithLocals(module, assignment.value, &.{}, top_level_locals.items) or !expressionSupportedWithLocals(module, target, &.{}, top_level_locals.items)) return false;
                            continue;
                        }
                        if (!expressionSupportedWithLocals(module, assignment.value, &.{}, top_level_locals.items)) return false;
                        if (lowering.localIndex(top_level_locals.items, assignment.name) == null) top_level_locals.append(module.allocator, assignment.name) catch return false;
                    },
                    else => if (!expressionSupportedWithLocals(module, id, &.{}, top_level_locals.items)) return false,
                }
            },
            else => return false,
        }
    }
    return expression_count > 0;
}
pub fn lower(allocator: std.mem.Allocator, module: *const ast.Module) !bytecode.Chunk {
    if (!supports(module)) return compatibility.lower(allocator, module);
    var functions: std.ArrayListUnmanaged(*const mir.Function) = .empty;
    defer functions.deinit(allocator);
    var lowered_functions: std.ArrayListUnmanaged(mir.Function) = .empty;
    defer for (lowered_functions.items) |*function| function.deinit();
    var function_statements: std.ArrayListUnmanaged(usize) = .empty;
    defer function_statements.deinit(allocator);
    for (module.statements.items, 0..) |statement, index| if (statement.kind == .function) try function_statements.append(allocator, index);
    var function_captures: std.ArrayListUnmanaged(ast_helpers.FunctionCaptureInfo) = .empty;
    defer function_captures.deinit(allocator);
    try ast_helpers.collectFunctionCaptures(allocator, module, function_statements.items, &function_captures);
    var function_index: usize = 0;
    for (module.statements.items) |statement| if (statement.kind == .function) {
        const capture_info = function_captures.items[function_index];
        const is_method = pipeline_support.methodOwner(module, statement.kind.function.body_first) != null;
        var source = try lowering.lowerFunction(allocator, module, statement.kind.function, function_index, capture_info.captures[0..capture_info.capture_count], is_method);
        errdefer source.deinit();
        try lowered_functions.append(allocator, source);
        try functions.append(allocator, &lowered_functions.items[lowered_functions.items.len - 1]);
        function_index += 1;
    };
    var main_source = hir.Function.init(allocator, "<module>");
    defer main_source.deinit();
    var top_level_locals: std.ArrayListUnmanaged([]const u8) = .empty;
    defer top_level_locals.deinit(allocator);
    var body_indices = std.AutoHashMap(usize, void).init(allocator);
    defer body_indices.deinit();
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |function| {
            for (function.body_first..function.body_first + function.body_count) |index| try body_indices.put(index, {});
            try top_level_locals.append(allocator, function.name);
        },
        .class_decl => |class_decl| {
            for (class_decl.body_first..class_decl.body_first + class_decl.body_count) |index| try body_indices.put(index, {});
            try top_level_locals.append(allocator, class_decl.name);
        },
        else => {},
    };
    for (module.statements.items, 0..) |statement, index| {
        if (body_indices.contains(index)) continue;
        if (statement.kind != .expression) continue;
        const expression_id = statement.kind.expression;
        switch (module.expressions.items[@as(usize, expression_id)].kind) {
            .assignment => |assignment| if (assignment.target == null and lowering.localIndex(top_level_locals.items, assignment.name) == null) try top_level_locals.append(allocator, assignment.name),
            else => {},
        }
    }
    for (module.expressions.items) |expression| if (expression.kind == .lambda) {
        const captures = try lowering.collectCaptures(allocator, module, expression.kind.lambda.body, module.parameters.items[expression.kind.lambda.params_first .. expression.kind.lambda.params_first + expression.kind.lambda.params_count], top_level_locals.items);
        defer allocator.free(captures);
        var source = try lowering.lowerLambda(allocator, module, expression.kind.lambda, function_index, captures);
        errdefer source.deinit();
        try lowered_functions.append(allocator, source);
        try functions.append(allocator, &lowered_functions.items[lowered_functions.items.len - 1]);
        function_index += 1;
    };
    main_source.local_count = top_level_locals.items.len;
    var final_expression: ?ast.ExprId = null;
    for (module.statements.items, 0..) |statement, index| {
        if (body_indices.contains(index)) continue;
        switch (statement.kind) {
            .function => |function| {
                const declaration_index = pipeline_helpers.functionIndex(module, function.name).?;
                const capture_info = function_captures.items[declaration_index];
                const captures = try allocator.alloc(hir.ValueId, capture_info.capture_count);
                for (capture_info.captures[0..capture_info.capture_count], 0..) |name, capture_index| captures[capture_index] = try main_source.appendValue(.dynamic, .{ .load_local = lowering.localIndex(top_level_locals.items, name) orelse return error.InvalidName }, statement.span.line);
                const value = if (capture_info.capture_count == 0) try main_source.appendValue(.dynamic, .{ .make_function = declaration_index }, statement.span.line) else try main_source.appendValue(.dynamic, .{ .make_closure = .{ .function = declaration_index, .captures = captures } }, statement.span.line);
                try main_source.appendEffect(.{ .store_local = .{ .slot = lowering.localIndex(top_level_locals.items, function.name).?, .value = value } }, statement.span.line);
            },
            .expression => |expression_id| switch (module.expressions.items[@as(usize, expression_id)].kind) {
                .assignment => |assignment| {
                    if (assignment.target) |target| {
                        const target_expression = switch (module.expressions.items[@as(usize, target)].kind) {
                            .index => |value| value,
                            else => return error.UnsupportedExpression,
                        };
                        const object = try lowering.lowerExpressionWithLocals(allocator, &main_source, module, target_expression.object, &.{}, top_level_locals.items, &.{});
                        const key = try lowering.lowerExpressionWithLocals(allocator, &main_source, module, target_expression.index, &.{}, top_level_locals.items, &.{});
                        const value = try lowering.lowerExpressionWithLocals(allocator, &main_source, module, assignment.value, &.{}, top_level_locals.items, &.{});
                        try main_source.appendEffect(.{ .store_index = .{ .object = object, .key = key, .value = value } }, module.expressions.items[@as(usize, expression_id)].span.line);
                        continue;
                    }
                    const value = try lowering.lowerExpressionWithLocals(allocator, &main_source, module, assignment.value, &.{}, top_level_locals.items, &.{});
                    try main_source.appendEffect(.{ .store_local = .{ .slot = lowering.localIndex(top_level_locals.items, assignment.name) orelse return error.InvalidExpression, .value = value } }, module.expressions.items[@as(usize, expression_id)].span.line);
                },
                else => final_expression = expression_id,
            },
            else => {},
        }
    }
    const expression_id = final_expression orelse return error.UnsupportedExpression;
    const result = try lowering.lowerExpressionWithLocals(allocator, &main_source, module, expression_id, &.{}, top_level_locals.items, &.{});
    try main_source.appendEffect(.{ .return_value = result }, module.expressions.items[@as(usize, expression_id)].span.line);
    var main = try mir.Function.lower(allocator, &main_source);
    defer main.deinit();
    var classes: std.ArrayListUnmanaged(bytecode.ClassInfo) = .empty;
    defer classes.deinit(allocator);
    var methods: std.ArrayListUnmanaged(bytecode.MethodInfo) = .empty;
    defer methods.deinit(allocator);
    for (module.statements.items) |statement| switch (statement.kind) {
        .class_decl => |class_decl| {
            const class_index = classes.items.len;
            try classes.append(allocator, .{ .name = class_decl.name, .base = if (class_decl.base) |base| pipeline_support.classIndex(module, base) else null });
            for (module.statements.items) |method_statement| switch (method_statement.kind) {
                .function => |function| if (function.body_first >= class_decl.body_first and function.body_first < class_decl.body_first + class_decl.body_count) try methods.append(allocator, .{ .class_index = class_index, .name = function.name, .function_index = pipeline_helpers.functionIndex(module, function.name).?, .visibility = @intFromEnum(function.visibility) }),
                else => {},
            };
        },
        else => {},
    };
    return mir_bytecode.lowerProgramWithMetadata(allocator, &main, functions.items, classes.items, methods.items);
}

fn functionBodySupported(module: *const ast.Module, first: usize, count: usize, params_first: usize, params_count: usize, captures: []const []const u8) bool {
    if (count == 0 or first >= module.statements.items.len) return false;
    const parameters = module.parameters.items[params_first .. params_first + params_count];
    var assigned_names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer assigned_names.deinit(module.allocator);
    const statement = module.statements.items[first];
    if (count > 1) {
        for (module.statements.items[first .. first + count - 1]) |assignment_statement| {
            const expression_id = switch (assignment_statement.kind) {
                .expression => |id| id,
                else => return false,
            };
            if (@as(usize, expression_id) >= module.expressions.items.len) return false;
            switch (module.expressions.items[expression_id].kind) {
                .assignment => |assignment| {
                    if (!expressionSupportedWithFunctions(module, assignment.value, parameters, captures)) return false;
                    if (assignment.target) |target| switch (module.expressions.items[@as(usize, target)].kind) {
                        .member => |member| if (!expressionSupportedWithFunctions(module, member.object, parameters, captures)) return false,
                        else => return false,
                    };
                    var known = false;
                    for (assigned_names.items) |name| {
                        if (std.mem.eql(u8, name, assignment.name)) known = true;
                    }
                    if (!known) assigned_names.append(module.allocator, assignment.name) catch return false;
                },
                else => return false,
            }
        }
    }
    if (count > 1 and module.statements.items[first + count - 1].kind != .return_stmt) return false;
    const terminal = module.statements.items[first + count - 1];
    return switch (statement.kind) {
        .expression => |id| if (module.expressions.items[@as(usize, id)].kind == .assignment) blk: {
            const assignment = module.expressions.items[@as(usize, id)].kind.assignment;
            const target = assignment.target orelse break :blk false;
            const member = switch (module.expressions.items[@as(usize, target)].kind) {
                .member => |value| value,
                else => break :blk false,
            };
            break :blk expressionSupportedWithFunctions(module, member.object, parameters, captures) and expressionSupportedWithFunctions(module, assignment.value, parameters, captures);
        } else false,
        .return_stmt => |value| if (value) |expression| expressionSupportedWithFunctions(module, expression, parameters, captures) else false,
        .control => |control| if (std.mem.eql(u8, control.keyword, "if") and control.condition != null and control.body_count == 1 and control.else_count == 1 and control.body_first < module.statements.items.len and control.else_first < module.statements.items.len) blk: {
            const condition = control.condition.?;
            const condition_expression = module.expressions.items[@as(usize, condition)];
            const condition_is_boolean = switch (condition_expression.kind) {
                .binary => |binary| binary.op == .equal or binary.op == .less,
                .boolean => true,
                else => false,
            };
            const then_statement = module.statements.items[control.body_first].kind;
            const else_statement = module.statements.items[control.else_first].kind;
            break :blk condition_is_boolean and expressionSupportedWithFunctions(module, condition, parameters, captures) and switch (then_statement) {
                .return_stmt => |value| value != null and expressionSupportedWithFunctions(module, value.?, parameters, captures),
                else => false,
            } and switch (else_statement) {
                .return_stmt => |value| value != null and expressionSupportedWithFunctions(module, value.?, parameters, captures),
                else => false,
            };
        } else if (std.mem.eql(u8, control.keyword, "while") and control.condition != null and control.body_count == 1 and control.body_first < module.statements.items.len) blk: {
            if (count < 2 or terminal.kind != .return_stmt) break :blk false;
            const condition = control.condition.?;
            if (!expressionSupportedWithLocals(module, condition, parameters, assigned_names.items)) break :blk false;
            const body_expression = switch (module.statements.items[control.body_first].kind) {
                .expression => |id| id,
                else => break :blk false,
            };
            const assignment = switch (module.expressions.items[body_expression].kind) {
                .assignment => |value| value,
                else => break :blk false,
            };
            if (lowering.localIndex(assigned_names.items, assignment.name) == null) break :blk false;
            break :blk expressionSupportedWithLocals(module, assignment.value, parameters, assigned_names.items) and switch (terminal.kind) {
                .return_stmt => |value| if (value) |expression| expressionSupportedWithLocals(module, expression, parameters, assigned_names.items) else false,
                else => false,
            };
        } else false,
        else => switch (terminal.kind) {
            .return_stmt => |value| if (value) |expression| switch (module.expressions.items[expression].kind) {
                .name => |name| pipeline_helpers.parameterIndex(parameters, name) != null or lowering.localIndex(assigned_names.items, name) != null,
                else => expressionSupportedWithLocals(module, expression, parameters, assigned_names.items),
            } else false,
            else => false,
        },
    };
}
fn expressionSupportedWithFunctions(module: *const ast.Module, id: ast.ExprId, parameters: []const ast.Parameter, captures: []const []const u8) bool {
    return pipeline_support.expressionSupportedWithFunctions(module, id, parameters, captures);
}
fn expressionSupportedWithLocals(module: *const ast.Module, id: ast.ExprId, parameters: []const ast.Parameter, locals: []const []const u8) bool {
    return pipeline_support.expressionSupportedWithLocals(module, id, parameters, locals);
}
