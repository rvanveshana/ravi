const std = @import("std");
const bytecode = @import("ravi_bytecode");
const config = @import("ravi_config");
const helpers = @import("helpers.zig");
const ast = @import("ravi_ast");
const ast_helpers = @import("ravi_ast_helpers");
const ast_compiler = @import("ast_compiler.zig");
const ast_statements = @import("ast_statements.zig");

pub const CompileError = std.mem.Allocator.Error || error{ NoExecutableExpression, InvalidNumber, UnsupportedOperator, InvalidName, InvalidFunction, InvalidExpression, PrivateAccess, UnterminatedCall };

const AstLoopContext = ast_helpers.LoopContext;
const AstFinallyContext = ast_helpers.FinallyContext;
const AstLambdaInfo = ast_helpers.LambdaInfo;

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    language: config.SourceLanguage = .kn,
    last_location: bytecode.SourceLocation = .{ .start_offset = 0, .end_offset = 0, .line = 1, .column = 1 },
    ast_state: ast_helpers.State = .{},
    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{ .allocator = allocator };
    }
    pub fn initWithLanguage(allocator: std.mem.Allocator, language: config.SourceLanguage) Compiler {
        return .{ .allocator = allocator, .language = language };
    }

    pub fn findAstFunction(self: *const Compiler, module: *const ast.Module, name: []const u8) ?usize {
        for (self.ast_state.function_statements, 0..) |statement_index, function_index| {
            const function = module.statements.items[statement_index].kind.function;
            if (std.mem.eql(u8, function.name, name)) return function_index;
        }
        return null;
    }

    pub fn findAstClass(module: *const ast.Module, name: []const u8) ?usize {
        var class_index: usize = 0;
        for (module.statements.items) |statement| switch (statement.kind) {
            .class_decl => |class_decl| {
                if (std.mem.eql(u8, class_decl.name, name)) return class_index;
                class_index += 1;
            },
            else => {},
        };
        return null;
    }

    /// Compile the scalar AST subset without consulting source tokens.
    pub fn compileAstModule(self: *Compiler, module: *const ast.Module) CompileError!bytecode.Chunk {
        var chunk = bytecode.Chunk.init(self.allocator);
        errdefer chunk.deinit();
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        defer names.deinit(self.allocator);
        var function_statements: std.ArrayListUnmanaged(usize) = .empty;
        defer function_statements.deinit(self.allocator);
        try ast_helpers.collectFunctionStatements(self.allocator, module, &function_statements);
        var function_captures: std.ArrayListUnmanaged(ast_helpers.FunctionCaptureInfo) = .empty;
        defer function_captures.deinit(self.allocator);
        try ast_helpers.collectFunctionCaptures(self.allocator, module, function_statements.items, &function_captures);
        var class_index: usize = 0;
        for (module.statements.items) |statement| switch (statement.kind) {
            .class_decl => |class_decl| {
                const base = if (class_decl.base) |base_name| blk: {
                    var candidate: usize = 0;
                    for (module.statements.items) |base_statement| switch (base_statement.kind) {
                        .class_decl => |candidate_class| {
                            if (std.mem.eql(u8, candidate_class.name, base_name)) break :blk candidate;
                            candidate += 1;
                        },
                        else => {},
                    };
                    break :blk null;
                } else null;
                const is_exception = if (class_decl.base) |base_name| std.mem.eql(u8, base_name, "Exception") or std.mem.eql(u8, base_name, "BaseException") or (base != null and chunk.classes.items[base.?].is_exception) else false;
                try chunk.classes.append(self.allocator, .{ .name = class_decl.name, .base = base, .is_exception = is_exception });
                for (function_statements.items, 0..) |statement_index, function_index| {
                    if (statement_index >= class_decl.body_first and statement_index < class_decl.body_first + class_decl.body_count) {
                        const method = module.statements.items[statement_index].kind.function;
                        try chunk.methods.append(self.allocator, .{ .class_index = class_index, .name = method.name, .function_index = function_index, .visibility = @intFromEnum(method.visibility) });
                    }
                }
                class_index += 1;
            },
            else => {},
        };
        for (function_statements.items, 0..) |statement_index, function_index| {
            const function = module.statements.items[statement_index].kind.function;
            var defaults: [64]?i64 = @splat(null);
            var fixed_count: usize = function.params_count;
            var varargs_index: ?usize = null;
            var kwargs_index: ?usize = null;
            for (module.parameters.items[function.params_first .. function.params_first + function.params_count], 0..) |parameter, parameter_index| {
                defaults[parameter_index] = parameter.default_value;
                switch (parameter.kind) {
                    .positional => {},
                    .variadic => varargs_index = parameter_index,
                    .keyword_variadic => kwargs_index = parameter_index,
                }
            }
            if (varargs_index) |index| fixed_count = index;
            if (kwargs_index) |index| {
                if (index < fixed_count) fixed_count = index;
            }
            _ = try chunk.addFunction(.{ .entry = 0, .arity = function.params_count, .fixed_count = fixed_count, .varargs_index = varargs_index, .kwargs_index = kwargs_index, .name = function.name, .defaults = defaults, .capture_count = function_captures.items[function_index].capture_count });
        }
        var lambdas: std.ArrayListUnmanaged(AstLambdaInfo) = .empty;
        defer lambdas.deinit(self.allocator);
        try ast_helpers.collectLambdaInfos(self.allocator, module, &lambdas);
        for (lambdas.items) |lambda| _ = try chunk.addFunction(.{ .entry = 0, .arity = lambda.params_count, .name = "<lambda>", .capture_count = lambda.capture_count });
        self.ast_state.lambdas = lambdas.items;
        self.ast_state.function_count = function_statements.items.len;
        defer {
            self.ast_state.lambdas = &.{};
            self.ast_state.function_count = 0;
            self.ast_state.active_captures = &.{};
            self.ast_state.function_statements = &.{};
            self.ast_state.function_captures = &.{};
        }
        self.ast_state.function_statements = function_statements.items;
        self.ast_state.function_captures = function_captures.items;
        var loops: std.ArrayListUnmanaged(AstLoopContext) = .empty;
        defer loops.deinit(self.allocator);
        var break_targets: std.ArrayListUnmanaged(usize) = .empty;
        defer break_targets.deinit(self.allocator);
        var continue_targets: std.ArrayListUnmanaged(usize) = .empty;
        defer continue_targets.deinit(self.allocator);
        self.ast_state.continue_targets = &continue_targets;
        defer self.ast_state.continue_targets = null;
        var finalizers: std.ArrayListUnmanaged(AstFinallyContext) = .empty;
        defer finalizers.deinit(self.allocator);
        self.ast_state.finalizers = &finalizers;
        defer self.ast_state.finalizers = null;
        try self.compileAstTopLevel(&chunk, module, &names, &function_statements, &loops, &break_targets);
        try chunk.emit(.{ .op = .halt });
        for (function_statements.items, 0..) |statement_index, function_index| {
            const function = module.statements.items[statement_index].kind.function;
            chunk.functions.items[function_index].entry = chunk.code.items.len;
            var function_names: std.ArrayListUnmanaged([]const u8) = .empty;
            defer function_names.deinit(self.allocator);
            for (module.statements.items) |statement| switch (statement.kind) {
                .class_decl => |class_decl| if (statement_index >= class_decl.body_first and statement_index < class_decl.body_first + class_decl.body_count) try function_names.append(self.allocator, "tanna"),
                else => {},
            };
            for (module.parameters.items[function.params_first .. function.params_first + function.params_count]) |parameter| try function_names.append(self.allocator, parameter.name);
            self.ast_state.active_captures = function_captures.items[function_index].captures[0..function_captures.items[function_index].capture_count];
            try self.compileAstStatements(&chunk, module, function.body_first, function.body_count, &function_names, true, &loops, &break_targets);
            self.ast_state.active_captures = &.{};
            try chunk.emit(.{ .op = .constant, .operand = 0 });
            try chunk.emit(.{ .op = .return_value });
        }
        for (lambdas.items, 0..) |lambda, lambda_index| {
            chunk.functions.items[self.ast_state.function_count + lambda_index].entry = chunk.code.items.len;
            var lambda_names: std.ArrayListUnmanaged([]const u8) = .empty;
            defer lambda_names.deinit(self.allocator);
            for (module.parameters.items[lambda.params_first .. lambda.params_first + lambda.params_count]) |parameter| try lambda_names.append(self.allocator, parameter.name);
            self.ast_state.active_captures = lambda.captures[0..lambda.capture_count];
            try self.compileAstExpression(&chunk, module, lambda.body, &lambda_names);
            self.ast_state.active_captures = &.{};
            try chunk.emit(.{ .op = .return_value });
        }
        return chunk;
    }

    fn compileAstFinalizers(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, names: *std.ArrayListUnmanaged([]const u8), loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        return ast_statements.finalizers(CompileError, self, chunk, module, names, loops, break_targets);
    }

    fn compileAstTopLevel(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, names: *std.ArrayListUnmanaged([]const u8), function_statements: *const std.ArrayListUnmanaged(usize), loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        return ast_statements.topLevel(CompileError, self, chunk, module, names, function_statements, loops, break_targets);
    }

    pub fn compileAstStatements(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, first: usize, count: usize, names: *std.ArrayListUnmanaged([]const u8), discard_expression: bool, loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        if (first > module.statements.items.len or count > module.statements.items.len - first) return error.InvalidExpression;
        var statement_index = first;
        while (statement_index < first + count) : (statement_index += 1) {
            const statement = module.statements.items[statement_index];
            switch (statement.kind) {
                .expression => |expression| {
                    try self.compileAstExpression(chunk, module, expression, names);
                    if (discard_expression) try chunk.emit(.{ .op = .pop });
                },
                .return_stmt => |expression| {
                    if (expression) |value| try self.compileAstExpression(chunk, module, value, names) else try chunk.emit(.{ .op = .constant, .operand = 0 });
                    try self.compileAstFinalizers(chunk, module, names, loops, break_targets);
                    try chunk.emit(.{ .op = .return_value });
                },
                .raise_stmt => |expression| {
                    if (expression) |value| try self.compileAstExpression(chunk, module, value, names) else try chunk.emit(.{ .op = .constant, .operand = 0 });
                    try chunk.emit(.{ .op = .raise_value });
                },
                .function => |function| {
                    var function_index: ?usize = null;
                    for (self.ast_state.function_statements, 0..) |declaration_index, candidate| if (declaration_index == statement_index) {
                        function_index = candidate;
                        break;
                    };
                    const index = function_index orelse return error.InvalidFunction;
                    const capture_info = self.ast_state.function_captures[index];
                    for (capture_info.captures[0..capture_info.capture_count]) |capture| {
                        if (helpers.findLocal(names.items, capture)) |slot| {
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                        } else if (helpers.findCapture(self.ast_state.active_captures, capture)) |capture_slot| {
                            try chunk.emit(.{ .op = .load_capture_ref, .operand = @intCast(capture_slot) });
                        } else return error.InvalidName;
                    }
                    try chunk.emit(.{ .op = if (capture_info.capture_count == 0) .make_function else .make_closure, .operand = @intCast(index) });
                    const slot = try helpers.localSlot(names, self.allocator, function.name);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                    try chunk.emit(.{ .op = .pop });
                    statement_index = function.body_first + function.body_count;
                    statement_index -= 1;
                },
                .try_stmt => |try_stmt| {
                    const begin_try = chunk.code.items.len;
                    try chunk.emit(.{ .op = .try_begin, .operand = 0 });
                    const finalizer_first = if (self.ast_state.finalizers) |finalizer_list| finalizer_list.items.len else 0;
                    if (try_stmt.finally_count != 0) if (self.ast_state.finalizers) |finalizer_list| try finalizer_list.append(self.allocator, .{ .first = try_stmt.finally_first, .count = try_stmt.finally_count });
                    try self.compileAstStatements(chunk, module, try_stmt.body_first, try_stmt.body_count, names, true, loops, break_targets);
                    if (self.ast_state.finalizers) |finalizer_list| finalizer_list.shrinkRetainingCapacity(finalizer_first);
                    try chunk.emit(.{ .op = .try_end });
                    if (try_stmt.finally_count != 0) try self.compileAstStatements(chunk, module, try_stmt.finally_first, try_stmt.finally_count, names, true, loops, break_targets);
                    const skip_handler = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump, .operand = 0 });
                    chunk.code.items[begin_try].operand = @intCast(chunk.code.items.len);
                    var no_match: ?usize = null;
                    if (try_stmt.except_type) |exception_type| {
                        try chunk.emit(.{ .op = .dup });
                        const type_name = try chunk.addString(exception_type);
                        try chunk.emit(.{ .op = .make_string, .operand = @intCast(type_name) });
                        try chunk.emit(.{ .op = .make_exception });
                        try chunk.emit(.{ .op = .exception_match });
                    } else if (try_stmt.except_match) |match| {
                        try chunk.emit(.{ .op = .dup });
                        try self.compileAstExpression(chunk, module, match, names);
                        try chunk.emit(.{ .op = .equal });
                        const match_jump = chunk.code.items.len;
                        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                        no_match = match_jump;
                    }
                    if (try_stmt.except_binding) |binding| {
                        const slot = try helpers.localSlot(names, self.allocator, binding);
                        try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                    }
                    if (try_stmt.except_count != 0) {
                        if (try_stmt.except_binding != null or try_stmt.except_match != null) {
                            try chunk.emit(.{ .op = .pop });
                        } else {
                            try chunk.emit(.{ .op = .pop });
                        }
                        try self.compileAstStatements(chunk, module, try_stmt.except_first, try_stmt.except_count, names, true, loops, break_targets);
                    } else {
                        try chunk.emit(.{ .op = .raise_value });
                    }
                    if (try_stmt.finally_count != 0) try self.compileAstStatements(chunk, module, try_stmt.finally_first, try_stmt.finally_count, names, true, loops, break_targets);
                    if (no_match) |match_jump| {
                        chunk.code.items[match_jump].operand = @intCast(chunk.code.items.len + 1);
                        try chunk.emit(.{ .op = .raise_value });
                    }
                    chunk.code.items[skip_handler].operand = @intCast(chunk.code.items.len);
                    statement_index = @max(statement_index + 1, try_stmt.body_first + try_stmt.body_count);
                    if (try_stmt.except_count != 0) statement_index = @max(statement_index, try_stmt.except_first + try_stmt.except_count);
                    if (try_stmt.finally_count != 0) statement_index = @max(statement_index, try_stmt.finally_first + try_stmt.finally_count);
                    statement_index -= 1;
                },
                .transfer => |transfer_keyword| {
                    if (std.mem.eql(u8, transfer_keyword, "pass")) {
                        // Intentional no-op statement.
                    } else if (std.mem.eql(u8, transfer_keyword, "break")) {
                        if (loops.items.len == 0) return error.UnsupportedOperator;
                        try self.compileAstFinalizers(chunk, module, names, loops, break_targets);
                        const jump = chunk.code.items.len;
                        try chunk.emit(.{ .op = .jump, .operand = 0 });
                        try break_targets.append(self.allocator, jump);
                    } else if (std.mem.eql(u8, transfer_keyword, "continue")) {
                        if (loops.items.len == 0) return error.UnsupportedOperator;
                        try self.compileAstFinalizers(chunk, module, names, loops, break_targets);
                        const context = loops.items[loops.items.len - 1];
                        const jump = chunk.code.items.len;
                        const pending = context.continue_target == std.math.maxInt(usize);
                        try chunk.emit(.{ .op = .jump, .operand = if (pending) 0 else @intCast(context.continue_target) });
                        if (pending) if (self.ast_state.continue_targets) |targets| try targets.append(self.allocator, jump);
                    } else return error.UnsupportedOperator;
                },
                .control => |control| {
                    if (std.mem.eql(u8, control.keyword, "for")) {
                        const iterable = control.iterable orelse return error.InvalidExpression;
                        const target = control.target orelse return error.InvalidExpression;
                        const collection_name = try std.fmt.allocPrint(self.allocator, "__ast_for_collection_{d}", .{names.items.len});
                        const index_name = try std.fmt.allocPrint(self.allocator, "__ast_for_index_{d}", .{names.items.len});
                        const collection_slot = try helpers.localSlot(names, self.allocator, collection_name);
                        const index_slot = try helpers.localSlot(names, self.allocator, index_name);
                        if (@as(usize, iterable) < module.expressions.items.len and module.expressions.items[iterable].kind == .call) {
                            const range_call = module.expressions.items[iterable].kind.call;
                            if (@as(usize, range_call.callee) < module.expressions.items.len and module.expressions.items[range_call.callee].kind == .name) {
                                const range_name = module.expressions.items[range_call.callee].kind.name;
                                const is_range = std.mem.eql(u8, range_name, if (self.language == .kn) "shreni" else "range") or std.mem.eql(u8, range_name, "range");
                                if (is_range and range_call.arg_count >= 1 and range_call.arg_count <= 3) {
                                    const current_name = try std.fmt.allocPrint(self.allocator, "__ast_range_current_{d}", .{names.items.len});
                                    const limit_name = try std.fmt.allocPrint(self.allocator, "__ast_range_limit_{d}", .{names.items.len});
                                    const step_name = try std.fmt.allocPrint(self.allocator, "__ast_range_step_{d}", .{names.items.len});
                                    const current_slot = try helpers.localSlot(names, self.allocator, current_name);
                                    const limit_slot = try helpers.localSlot(names, self.allocator, limit_name);
                                    const step_slot = try helpers.localSlot(names, self.allocator, step_name);
                                    if (range_call.first_arg > module.call_args.items.len or range_call.arg_count > module.call_args.items.len - range_call.first_arg) return error.InvalidExpression;
                                    const range_args = module.call_args.items[range_call.first_arg .. range_call.first_arg + range_call.arg_count];
                                    if (range_call.arg_count == 1) try chunk.emit(.{ .op = .constant, .operand = 0 }) else try self.compileAstExpression(chunk, module, range_args[0], names);
                                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(current_slot) });
                                    try chunk.emit(.{ .op = .pop });
                                    const limit_argument: usize = if (range_call.arg_count == 1) 0 else 1;
                                    try self.compileAstExpression(chunk, module, range_args[limit_argument], names);
                                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(limit_slot) });
                                    try chunk.emit(.{ .op = .pop });
                                    if (range_call.arg_count == 3) try self.compileAstExpression(chunk, module, range_args[2], names) else try chunk.emit(.{ .op = .constant, .operand = 1 });
                                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(step_slot) });
                                    try chunk.emit(.{ .op = .pop });
                                    const loop_start = chunk.code.items.len;
                                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(limit_slot) });
                                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(step_slot) });
                                    try chunk.emit(.{ .op = .range_condition });
                                    const exit_jump = chunk.code.items.len;
                                    try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                                    const target_slot = try helpers.localSlot(names, self.allocator, target);
                                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(target_slot) });
                                    try chunk.emit(.{ .op = .pop });
                                    const break_first = break_targets.items.len;
                                    const continue_first = if (self.ast_state.continue_targets) |targets| targets.items.len else 0;
                                    try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = break_first, .continues_first = continue_first });
                                    try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
                                    _ = loops.pop();
                                    const increment_start = chunk.code.items.len;
                                    if (self.ast_state.continue_targets) |targets| {
                                        for (targets.items[continue_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(increment_start);
                                        targets.shrinkRetainingCapacity(continue_first);
                                    }
                                    const packed_slots = (@as(i64, @intCast(current_slot)) << 32) | @as(i64, @intCast(step_slot));
                                    try chunk.emit(.{ .op = .range_step, .operand = packed_slots });
                                    try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                                    chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
                                    for (break_targets.items[break_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(chunk.code.items.len);
                                    break_targets.shrinkRetainingCapacity(break_first);
                                    statement_index = @max(statement_index + 1, control.body_first + control.body_count);
                                    statement_index -= 1;
                                    continue;
                                }
                            }
                        }
                        if (@as(usize, iterable) < module.expressions.items.len and module.expressions.items[iterable].kind == .integer) {
                            const current_name = try std.fmt.allocPrint(self.allocator, "__ast_range_current_{d}", .{names.items.len});
                            const limit_name = try std.fmt.allocPrint(self.allocator, "__ast_range_limit_{d}", .{names.items.len});
                            const step_name = try std.fmt.allocPrint(self.allocator, "__ast_range_step_{d}", .{names.items.len});
                            const current_slot = try helpers.localSlot(names, self.allocator, current_name);
                            const limit_slot = try helpers.localSlot(names, self.allocator, limit_name);
                            const step_slot = try helpers.localSlot(names, self.allocator, step_name);
                            try chunk.emit(.{ .op = .constant, .operand = 0 });
                            try chunk.emit(.{ .op = .store_local, .operand = @intCast(current_slot) });
                            try chunk.emit(.{ .op = .pop });
                            try self.compileAstExpression(chunk, module, iterable, names);
                            try chunk.emit(.{ .op = .store_local, .operand = @intCast(limit_slot) });
                            try chunk.emit(.{ .op = .pop });
                            try chunk.emit(.{ .op = .constant, .operand = 1 });
                            try chunk.emit(.{ .op = .store_local, .operand = @intCast(step_slot) });
                            try chunk.emit(.{ .op = .pop });
                            const loop_start = chunk.code.items.len;
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(limit_slot) });
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(step_slot) });
                            try chunk.emit(.{ .op = .range_condition });
                            const exit_jump = chunk.code.items.len;
                            try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                            const target_slot = try helpers.localSlot(names, self.allocator, target);
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                            try chunk.emit(.{ .op = .store_local, .operand = @intCast(target_slot) });
                            try chunk.emit(.{ .op = .pop });
                            const break_first = break_targets.items.len;
                            const continue_first = if (self.ast_state.continue_targets) |targets| targets.items.len else 0;
                            try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = break_first });
                            try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
                            _ = loops.pop();
                            const increment_start = chunk.code.items.len;
                            if (self.ast_state.continue_targets) |targets| {
                                for (targets.items[continue_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(increment_start);
                                targets.shrinkRetainingCapacity(continue_first);
                            }
                            try chunk.emit(.{ .op = .range_step, .operand = (@as(i64, @intCast(current_slot)) << 32) | @as(i64, @intCast(step_slot)) });
                            try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                            chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
                            for (break_targets.items[break_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(chunk.code.items.len);
                            break_targets.shrinkRetainingCapacity(break_first);
                            statement_index = @max(statement_index + 1, control.body_first + control.body_count);
                            statement_index -= 1;
                            continue;
                        }
                        try self.compileAstExpression(chunk, module, iterable, names);
                        try chunk.emit(.{ .op = .iterable });
                        try chunk.emit(.{ .op = .store_local, .operand = @intCast(collection_slot) });
                        try chunk.emit(.{ .op = .pop });
                        try chunk.emit(.{ .op = .constant, .operand = 0 });
                        try chunk.emit(.{ .op = .store_local, .operand = @intCast(index_slot) });
                        try chunk.emit(.{ .op = .pop });
                        const loop_start = chunk.code.items.len;
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(collection_slot) });
                        try chunk.emit(.{ .op = .length });
                        try chunk.emit(.{ .op = .less });
                        const exit_jump = chunk.code.items.len;
                        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(collection_slot) });
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
                        try chunk.emit(.{ .op = .index });
                        const target_slot = try helpers.localSlot(names, self.allocator, target);
                        try chunk.emit(.{ .op = .store_local, .operand = @intCast(target_slot) });
                        try chunk.emit(.{ .op = .pop });
                        const break_first = break_targets.items.len;
                        const continue_first = if (self.ast_state.continue_targets) |targets| targets.items.len else 0;
                        try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = break_first, .continues_first = continue_first });
                        try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
                        _ = loops.pop();
                        const increment_start = chunk.code.items.len;
                        if (self.ast_state.continue_targets) |targets| {
                            for (targets.items[continue_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(increment_start);
                            targets.shrinkRetainingCapacity(continue_first);
                        }
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
                        try chunk.emit(.{ .op = .constant, .operand = 1 });
                        try chunk.emit(.{ .op = .add });
                        try chunk.emit(.{ .op = .store_local, .operand = @intCast(index_slot) });
                        try chunk.emit(.{ .op = .pop });
                        try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                        chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
                        for (break_targets.items[break_first..]) |target_jump| chunk.code.items[target_jump].operand = @intCast(chunk.code.items.len);
                        break_targets.shrinkRetainingCapacity(break_first);
                    } else if (std.mem.eql(u8, control.keyword, "if") or std.mem.eql(u8, control.keyword, "elif")) {
                        const condition = control.condition orelse return error.InvalidExpression;
                        try self.compileAstExpression(chunk, module, condition, names);
                        const false_jump = chunk.code.items.len;
                        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                        try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
                        if (control.else_count != 0) {
                            const end_jump = chunk.code.items.len;
                            try chunk.emit(.{ .op = .jump, .operand = 0 });
                            chunk.code.items[false_jump].operand = @intCast(chunk.code.items.len);
                            try self.compileAstStatements(chunk, module, control.else_first, control.else_count, names, true, loops, break_targets);
                            chunk.code.items[end_jump].operand = @intCast(chunk.code.items.len);
                        } else chunk.code.items[false_jump].operand = @intCast(chunk.code.items.len);
                    } else if (std.mem.eql(u8, control.keyword, "while")) {
                        const loop_start = chunk.code.items.len;
                        const condition = control.condition orelse return error.InvalidExpression;
                        try self.compileAstExpression(chunk, module, condition, names);
                        const exit_jump = chunk.code.items.len;
                        try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                        const break_first = break_targets.items.len;
                        try loops.append(self.allocator, .{ .continue_target = loop_start, .breaks_first = break_first });
                        try self.compileAstStatements(chunk, module, control.body_first, control.body_count, names, true, loops, break_targets);
                        _ = loops.pop();
                        try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                        chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
                        for (break_targets.items[break_first..]) |target| chunk.code.items[target].operand = @intCast(chunk.code.items.len);
                        break_targets.shrinkRetainingCapacity(break_first);
                    } else return error.UnsupportedOperator;
                    statement_index = @max(statement_index + 1, control.body_first + control.body_count);
                    if (control.else_count != 0) statement_index = @max(statement_index, control.else_first + control.else_count);
                    statement_index -= 1;
                },
                else => return error.UnsupportedOperator,
            }
        }
    }

    fn compileAstExpression(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, expression_id: ast.ExprId, names: *std.ArrayListUnmanaged([]const u8)) CompileError!void {
        return ast_compiler.expression(CompileError, self, chunk, module, expression_id, names);
    }
};
