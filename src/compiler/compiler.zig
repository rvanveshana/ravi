const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const config = @import("ravi_config");
const expression_runtime = @import("expressions.zig");
const model = @import("model.zig");
const helpers = @import("helpers.zig");
const call_codegen = @import("calls.zig");
const builtins = @import("builtins.zig");
const ast = @import("ravi_ast");
const ast_helpers = @import("ast_helpers.zig");
const ast_compiler = @import("ast_compiler.zig");
const ast_statements = @import("ast_statements.zig");
const class_declarations = @import("declarations.zig");

pub const CompileError = std.mem.Allocator.Error || error{ NoExecutableExpression, InvalidNumber, UnsupportedOperator, InvalidName, InvalidFunction, InvalidExpression, PrivateAccess, UnterminatedCall };

const FunctionDecl = model.FunctionDecl;
const LoopContext = model.LoopContext;
const RangeParts = model.RangeParts;
const AstLoopContext = ast_helpers.LoopContext;
const AstFinallyContext = ast_helpers.FinallyContext;
const AstLambdaInfo = ast_helpers.LambdaInfo;

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    language: config.SourceLanguage = .kn,
    active_captures: [64][]const u8 = undefined,
    active_capture_count: usize = 0,
    active_function: ?[]const u8 = null,
    active_class: ?usize = null,
    last_location: bytecode.SourceLocation = .{ .start_offset = 0, .end_offset = 0, .line = 1, .column = 1 },
    class_names: [64][]const u8 = undefined,
    class_bases: [64]?[]const u8 = undefined,
    class_body_first: [64]usize = undefined,
    class_body_end: [64]usize = undefined,
    class_count: usize = 0,
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

    pub fn emitGuardedInteger(self: *Compiler, value: i64) CompileError!bytecode.Chunk {
        var chunk = bytecode.Chunk.init(self.allocator);
        errdefer chunk.deinit();
        try chunk.emit(.{ .op = .constant, .operand = value });
        try chunk.emit(.{ .op = .guard_integer });
        try chunk.emit(.{ .op = .return_value });
        return chunk;
    }

    pub fn compileExpression(self: *Compiler, tokens: []const lexer.Token) CompileError!bytecode.Chunk {
        var chunk = bytecode.Chunk.init(self.allocator);
        errdefer chunk.deinit();
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        defer names.deinit(self.allocator);
        try self.compileRange(&chunk, tokens, &names, &.{});
        try chunk.emit(.{ .op = .return_value });
        return chunk;
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
                try chunk.classes.append(self.allocator, .{ .name = class_decl.name, .base = base });
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
                    if (try_stmt.except_match) |match| {
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
                    if (try_stmt.except_binding != null or try_stmt.except_match != null) try chunk.emit(.{ .op = .pop });
                    if (try_stmt.except_count != 0) try self.compileAstStatements(chunk, module, try_stmt.except_first, try_stmt.except_count, names, true, loops, break_targets) else try chunk.emit(.{ .op = .raise_value });
                    if (try_stmt.finally_count != 0) try self.compileAstStatements(chunk, module, try_stmt.finally_first, try_stmt.finally_count, names, true, loops, break_targets);
                    if (no_match) |match_jump| {
                        chunk.code.items[match_jump].operand = @intCast(chunk.code.items.len);
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
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(collection_slot) });
                        try chunk.emit(.{ .op = .length });
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
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

    pub fn compileProgram(self: *Compiler, tokens: []const lexer.Token) CompileError!bytecode.Chunk {
        var chunk = bytecode.Chunk.init(self.allocator);
        errdefer chunk.deinit();
        var declarations: std.ArrayListUnmanaged(FunctionDecl) = .empty;
        defer declarations.deinit(self.allocator);
        var params: std.ArrayListUnmanaged([]const u8) = .empty;
        defer params.deinit(self.allocator);
        self.class_count = 0;
        try self.collectClasses(tokens);
        for (self.class_names[0..self.class_count], 0..) |name, class_index| {
            const base_name = self.class_bases[class_index] orelse {
                _ = try chunk.addClass(.{ .name = name });
                continue;
            };
            const base_index = self.findClass(base_name) orelse return error.InvalidName;
            _ = try chunk.addClass(.{ .name = name, .base = base_index });
        }
        try self.collectFunctions(tokens, &declarations, &params);
        try self.collectLambdas(tokens, &declarations, &params);
        for (declarations.items) |decl| _ = try chunk.addFunction(.{ .entry = 0, .arity = decl.params_count, .fixed_count = decl.fixed_count, .varargs_index = decl.varargs_index, .kwargs_index = decl.kwargs_index, .name = decl.name, .defaults = decl.defaults, .capture_count = decl.capture_count, .resumable = decl.resumable, .suspension_count = decl.suspension_count });
        for (declarations.items, 0..) |decl, function_index| if (decl.method) {
            for (0..self.class_count) |class_index| {
                if (decl.body_first >= self.class_body_first[class_index] and decl.body_first < self.class_body_end[class_index]) {
                    try chunk.methods.append(self.allocator, .{ .class_index = class_index, .name = decl.name, .function_index = function_index, .visibility = @intFromEnum(decl.visibility) });
                    break;
                }
            }
        };
        var names: std.ArrayListUnmanaged([]const u8) = .empty;
        defer names.deinit(self.allocator);
        var loops: std.ArrayListUnmanaged(LoopContext) = .empty;
        defer loops.deinit(self.allocator);
        var break_targets: std.ArrayListUnmanaged(usize) = .empty;
        defer break_targets.deinit(self.allocator);
        var continue_targets: std.ArrayListUnmanaged(usize) = .empty;
        defer continue_targets.deinit(self.allocator);
        try self.compileLines(&chunk, tokens, 0, tokens.len, &names, declarations.items, &loops, &break_targets, &continue_targets);
        try chunk.emit(.{ .op = .return_value });
        for (declarations.items, 0..) |decl, function_index| {
            chunk.functions.items[function_index].entry = chunk.code.items.len;
            names.clearRetainingCapacity();
            if (decl.method) try names.append(self.allocator, "tanna");
            const p_end = decl.params_first + decl.params_count;
            try names.appendSlice(self.allocator, params.items[decl.params_first..p_end]);
            loops.clearRetainingCapacity();
            break_targets.clearRetainingCapacity();
            continue_targets.clearRetainingCapacity();
            self.active_captures = decl.captures;
            self.active_capture_count = decl.capture_count;
            self.active_function = decl.name;
            self.active_class = if (decl.method) blk: {
                for (0..self.class_count) |class_index| {
                    if (decl.body_first >= self.class_body_first[class_index] and decl.body_first < self.class_body_end[class_index]) break :blk class_index;
                }
                break :blk null;
            } else null;
            if (decl.anonymous) {
                try self.compileRange(&chunk, tokens[decl.body_first..decl.body_end], &names, declarations.items);
                try chunk.emit(.{ .op = .return_value });
            } else {
                try self.compileLines(&chunk, tokens, decl.body_first, decl.body_end, &names, declarations.items, &loops, &break_targets, &continue_targets);
                try chunk.emit(.{ .op = .constant, .operand = 0 });
                try chunk.emit(.{ .op = .return_value });
            }
        }
        self.active_capture_count = 0;
        self.active_function = null;
        self.active_class = null;
        return chunk;
    }

    fn collectClasses(self: *Compiler, tokens: []const lexer.Token) CompileError!void {
        return class_declarations.collectClasses(CompileError, self, tokens);
    }

    fn collectFunctions(self: *Compiler, tokens: []const lexer.Token, declarations: *std.ArrayListUnmanaged(FunctionDecl), params: *std.ArrayListUnmanaged([]const u8)) !void {
        var i: usize = 0;
        while (i < tokens.len) {
            if (tokens[i].kind != .keyword or !self.keyword(tokens[i], "function")) {
                i += 1;
                continue;
            }
            const name_index = i + 1;
            if (name_index >= tokens.len or tokens[name_index].kind != .identifier) {
                i += 1;
                continue;
            }
            var header_end = name_index + 1;
            while (header_end < tokens.len and tokens[header_end].kind != .newline and tokens[header_end].kind != .eof) header_end += 1;
            const first_param = params.items.len;
            var arity: usize = 0;
            var fixed_count: usize = 0;
            var varargs_index: ?usize = null;
            var kwargs_index: ?usize = null;
            var defaults: [64]?i64 = @splat(null);
            var param_types: [64]?[]const u8 = @splat(null);
            var p = name_index + 1;
            while (p < header_end and tokens[p].kind != .l_paren) p += 1;
            if (p < header_end) {
                p += 1;
                while (p < header_end and tokens[p].kind != .r_paren) {
                    if (tokens[p].kind == .identifier and (p == name_index + 2 or tokens[p - 1].kind == .comma or tokens[p - 1].kind == .l_paren or (tokens[p - 1].kind == .operator and std.mem.eql(u8, tokens[p - 1].lexeme, "*")))) {
                        try params.append(self.allocator, tokens[p].lexeme);
                        defaults[arity] = null;
                        const star = p > 0 and tokens[p - 1].kind == .operator and std.mem.eql(u8, tokens[p - 1].lexeme, "*");
                        const double_star = p > 1 and star and tokens[p - 2].kind == .operator and std.mem.eql(u8, tokens[p - 2].lexeme, "*");
                        if (double_star) kwargs_index = arity else if (star) varargs_index = arity else fixed_count += 1;
                        var value_at = p + 1;
                        if (value_at + 2 < header_end and tokens[value_at].kind == .colon) {
                            param_types[arity] = tokens[value_at + 1].lexeme;
                            value_at += 2;
                        }
                        if (value_at + 1 < header_end and tokens[value_at].kind == .operator and std.mem.eql(u8, tokens[value_at].lexeme, "=") and tokens[value_at + 1].kind == .number) {
                            defaults[arity] = std.fmt.parseInt(i64, tokens[value_at + 1].lexeme, 10) catch return error.InvalidNumber;
                            p = value_at + 1;
                        }
                        arity += 1;
                    }
                    p += 1;
                }
            }
            var body_first = header_end + 1;
            if (body_first < tokens.len and tokens[body_first].kind == .indent) body_first += 1;
            const body_after = helpers.skipSuite(tokens, header_end + 1);
            const body_end = if (body_after > 0) body_after - 1 else body_first;
            var param_names: [64][]const u8 = undefined;
            var name_index_in_params: usize = 0;
            while (name_index_in_params < arity) : (name_index_in_params += 1) param_names[name_index_in_params] = params.items[first_param + name_index_in_params];
            var captures: [64][]const u8 = undefined;
            var capture_count: usize = 0;
            var resumable = false;
            var suspension_count: usize = 0;
            var cursor = body_first;
            var nested_depth: usize = 0;
            while (cursor < body_end) : (cursor += 1) {
                if (tokens[cursor].kind == .keyword and self.keyword(tokens[cursor], "function")) {
                    nested_depth += 1;
                }
                if (nested_depth > 0) {
                    if (tokens[cursor].kind == .dedent) nested_depth -= 1;
                    continue;
                }
                if (tokens[cursor].kind != .identifier) continue;
                var parameter = false;
                for (param_names[0..arity]) |name| {
                    if (std.mem.eql(u8, name, tokens[cursor].lexeme)) parameter = true;
                }
                if (parameter) continue;
                var duplicate = false;
                for (captures[0..capture_count]) |name| {
                    if (std.mem.eql(u8, name, tokens[cursor].lexeme)) duplicate = true;
                }
                if (!duplicate and capture_count < captures.len) {
                    captures[capture_count] = tokens[cursor].lexeme;
                    capture_count += 1;
                }
            }
            var suspension_cursor = body_first;
            var suspension_nested_depth: usize = 0;
            while (suspension_cursor < body_end) : (suspension_cursor += 1) {
                const token = tokens[suspension_cursor];
                if (token.kind == .keyword and self.keyword(token, "function")) {
                    suspension_nested_depth += 1;
                    continue;
                }
                if (suspension_nested_depth > 0) {
                    if (token.kind == .dedent) suspension_nested_depth -= 1;
                    continue;
                }
                if (token.kind == .keyword and (self.keyword(token, "yield") or self.keyword(token, "taru"))) {
                    resumable = true;
                    suspension_count += 1;
                }
            }
            var method = false;
            var visibility: model.Visibility = .public;
            if (i > 0) {
                const modifier = tokens[i - 1].lexeme;
                if (std.mem.eql(u8, modifier, "swanta") or std.mem.eql(u8, modifier, "private")) visibility = .private else if (std.mem.eql(u8, modifier, "vansha") or std.mem.eql(u8, modifier, "protected")) visibility = .protected else if (std.mem.eql(u8, modifier, "olage") or std.mem.eql(u8, modifier, "internal")) visibility = .internal;
            }
            for (0..self.class_count) |class_index| if (i >= self.class_body_first[class_index] and i < self.class_body_end[class_index]) {
                method = true;
                break;
            };
            try declarations.append(self.allocator, .{ .name = tokens[name_index].lexeme, .params_first = first_param, .params_count = arity, .fixed_count = fixed_count, .varargs_index = varargs_index, .kwargs_index = kwargs_index, .defaults = defaults, .param_names = param_names, .param_types = param_types, .captures = captures, .capture_count = capture_count, .body_first = body_first, .body_end = body_end, .method = method, .visibility = visibility, .resumable = resumable, .suspension_count = suspension_count });
            i += 1;
        }
    }

    fn collectLambdas(self: *Compiler, tokens: []const lexer.Token, declarations: *std.ArrayListUnmanaged(FunctionDecl), params: *std.ArrayListUnmanaged([]const u8)) !void {
        var cursor: usize = 0;
        var lambda_number: usize = 0;
        while (cursor < tokens.len) : (cursor += 1) {
            if (tokens[cursor].kind != .keyword or !self.keyword(tokens[cursor], "function") or cursor + 1 >= tokens.len or tokens[cursor + 1].kind != .l_paren) continue;
            var close = cursor + 2;
            while (close < tokens.len and tokens[close].kind != .r_paren) close += 1;
            if (close >= tokens.len) continue;
            var arrow_pos = close + 1;
            if (arrow_pos < tokens.len and tokens[arrow_pos].kind == .arrow) {
                arrow_pos += 1;
                if (arrow_pos < tokens.len and tokens[arrow_pos].kind == .identifier) arrow_pos += 1;
            }
            if (arrow_pos >= tokens.len or tokens[arrow_pos].kind != .fat_arrow) continue;
            const first_param = params.items.len;
            var arity: usize = 0;
            var p = cursor + 2;
            while (p < close) : (p += 1) if (tokens[p].kind == .identifier and (p == cursor + 2 or tokens[p - 1].kind == .comma)) {
                try params.append(self.allocator, tokens[p].lexeme);
                arity += 1;
            };
            const body_first_pos = arrow_pos + 1;
            var body_end = body_first_pos;
            while (body_end < tokens.len and tokens[body_end].kind != .newline and tokens[body_end].kind != .eof) body_end += 1;
            var names: [64][]const u8 = undefined;
            for (0..arity) |index| names[index] = params.items[first_param + index];
            var captures: [64][]const u8 = undefined;
            var capture_count: usize = 0;
            var body_cursor = body_first_pos;
            while (body_cursor < body_end) : (body_cursor += 1) {
                if (tokens[body_cursor].kind != .identifier) continue;
                var parameter = false;
                for (params.items[first_param .. first_param + arity]) |name| {
                    if (std.mem.eql(u8, name, tokens[body_cursor].lexeme)) parameter = true;
                }
                if (parameter) continue;
                var duplicate = false;
                for (captures[0..capture_count]) |name| {
                    if (std.mem.eql(u8, name, tokens[body_cursor].lexeme)) duplicate = true;
                }
                if (!duplicate and capture_count < 64) {
                    captures[capture_count] = tokens[body_cursor].lexeme;
                    capture_count += 1;
                }
            }
            try declarations.append(self.allocator, .{ .name = try std.fmt.allocPrint(self.allocator, "__lambda{d}", .{lambda_number}), .params_first = first_param, .params_count = arity, .fixed_count = arity, .param_names = names, .captures = captures, .capture_count = capture_count, .body_first = body_first_pos, .body_end = body_end, .anonymous = true });
            lambda_number += 1;
            cursor = body_end;
        }
    }

    fn compileLines(self: *Compiler, chunk: *bytecode.Chunk, tokens: []const lexer.Token, begin: usize, finish: usize, names: *std.ArrayListUnmanaged([]const u8), functions: []const FunctionDecl, loops: *std.ArrayListUnmanaged(LoopContext), break_targets: *std.ArrayListUnmanaged(usize), continue_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        var start = begin;
        while (start < finish) {
            while (start < finish and (tokens[start].kind == .newline or tokens[start].kind == .indent or tokens[start].kind == .dedent or tokens[start].kind == .comment)) start += 1;
            if (start >= finish) break;
            var end = start;
            while (end < finish and tokens[end].kind != .newline and tokens[end].kind != .eof) end += 1;
            self.last_location = helpers.sourceLocation(tokens[start]);
            chunk.setSourceLocation(self.last_location);
            if (tokens[start].kind == .identifier and start + 1 < end and tokens[start + 1].kind == .keyword and self.keyword(tokens[start + 1], "from")) {
                start = end + 1;
                continue;
            }
            if (self.active_function == null and tokens[start].kind == .keyword and (self.keyword(tokens[start], "function") or self.keyword(tokens[start], "class"))) {
                start = helpers.skipSuite(tokens, end + 1);
                continue;
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "break")) {
                const jump = chunk.code.items.len;
                try chunk.emit(.{ .op = .jump, .operand = 0 });
                try break_targets.append(self.allocator, jump);
                start = end + 1;
                continue;
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "continue")) {
                if (loops.items.len == 0) return error.UnsupportedOperator;
                const context = loops.items[loops.items.len - 1];
                const jump = chunk.code.items.len;
                const pending = context.continue_target == std.math.maxInt(usize);
                try chunk.emit(.{ .op = .jump, .operand = if (pending) 0 else @intCast(context.continue_target) });
                if (pending) try continue_targets.append(self.allocator, jump);
                start = end + 1;
                continue;
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "pass")) {
                start = end + 1;
                continue;
            }
            if (tokens[start].kind == .keyword and (self.keyword(tokens[start], "if") or self.keyword(tokens[start], "while"))) {
                const colon = helpers.findColon(tokens, start, end) orelse return error.UnsupportedOperator;
                const loop_start = chunk.code.items.len;
                try self.compileRange(chunk, tokens[start + 1 .. colon], names, functions);
                const jump_index = chunk.code.items.len;
                try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                const body_first = if (end + 1 < finish and tokens[end + 1].kind == .indent) end + 2 else end + 1;
                const body_after = helpers.skipSuite(tokens, end + 1);
                if (self.keyword(tokens[start], "while")) {
                    const context_start = break_targets.items.len;
                    const continue_start = continue_targets.items.len;
                    try loops.append(self.allocator, .{ .continue_target = loop_start, .breaks_first = context_start, .continues_first = continue_start });
                    try self.compileLines(chunk, tokens, body_first, body_after - 1, names, functions, loops, break_targets, continue_targets);
                    _ = loops.pop();
                    try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                    chunk.code.items[jump_index].operand = @intCast(chunk.code.items.len);
                    for (break_targets.items[context_start..]) |target| chunk.code.items[target].operand = @intCast(chunk.code.items.len);
                    break_targets.shrinkRetainingCapacity(context_start);
                    continue_targets.shrinkRetainingCapacity(continue_start);
                    start = body_after;
                    continue;
                }
                try self.compileLines(chunk, tokens, body_first, body_after - 1, names, functions, loops, break_targets, continue_targets);
                const next = helpers.skipLineTrivia(tokens, body_after);
                if (next < finish and self.keyword(tokens[next], "else")) {
                    var else_end = next;
                    while (else_end < finish and tokens[else_end].kind != .newline and tokens[else_end].kind != .eof) else_end += 1;
                    const else_first = if (else_end + 1 < finish and tokens[else_end + 1].kind == .indent) else_end + 2 else else_end + 1;
                    const else_after = helpers.skipSuite(tokens, else_end + 1);
                    const end_jump = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump, .operand = 0 });
                    chunk.code.items[jump_index].operand = @intCast(chunk.code.items.len);
                    try self.compileLines(chunk, tokens, else_first, else_after - 1, names, functions, loops, break_targets, continue_targets);
                    chunk.code.items[end_jump].operand = @intCast(chunk.code.items.len);
                    start = else_after;
                } else {
                    chunk.code.items[jump_index].operand = @intCast(chunk.code.items.len);
                    start = body_after;
                }
                continue;
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "for")) {
                const colon = helpers.findColon(tokens, start, end) orelse return error.UnsupportedOperator;
                if (start + 1 >= colon or tokens[start + 1].kind != .identifier) return error.InvalidName;
                var in_index: ?usize = null;
                for (start + 2..colon) |candidate| if (tokens[candidate].kind == .keyword and self.keyword(tokens[candidate], "in")) {
                    in_index = candidate;
                    break;
                };
                const iterable_at = in_index orelse return error.UnsupportedOperator;
                const loop_slot = try helpers.localSlot(names, self.allocator, tokens[start + 1].lexeme);
                const loop_id = loops.items.len;
                const step_name = try std.fmt.allocPrint(self.allocator, "__ravi_step_{d}", .{loop_id});
                const current_name = try std.fmt.allocPrint(self.allocator, "__ravi_current_{d}", .{loop_id});
                const step_slot = try helpers.localSlot(names, self.allocator, step_name);
                const current_slot = try helpers.localSlot(names, self.allocator, current_name);
                const iterable_tokens = tokens[iterable_at + 1 .. colon];
                var is_collection_expression = iterable_tokens.len > 0 and (iterable_tokens[0].kind == .l_bracket or iterable_tokens[0].kind == .l_brace);
                if (!is_collection_expression and helpers.parseRangeCall(iterable_tokens) == null) {
                    // Method/function calls can produce iterable collections (for example
                    // `for key in scores.kili()`).  Keep the numeric shorthand (`for i in n`)
                    // on the range path, but lower call expressions through collection indexing.
                    for (iterable_tokens) |token| if (token.kind == .l_paren) {
                        is_collection_expression = true;
                        break;
                    };
                }
                if (is_collection_expression) {
                    const iterable_name = try std.fmt.allocPrint(self.allocator, "__ravi_iterable_{d}", .{loop_id});
                    const index_name = try std.fmt.allocPrint(self.allocator, "__ravi_index_{d}", .{loop_id});
                    const iterable_slot = try helpers.localSlot(names, self.allocator, iterable_name);
                    const index_slot = try helpers.localSlot(names, self.allocator, index_name);
                    try self.compileRange(chunk, iterable_tokens, names, functions);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(iterable_slot) });
                    try chunk.emit(.{ .op = .pop });
                    try chunk.emit(.{ .op = .constant, .operand = 0 });
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(index_slot) });
                    try chunk.emit(.{ .op = .pop });
                    const collection_loop = chunk.code.items.len;
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(iterable_slot) });
                    try chunk.emit(.{ .op = .length });
                    try chunk.emit(.{ .op = .less });
                    const collection_exit = chunk.code.items.len;
                    try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(iterable_slot) });
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
                    try chunk.emit(.{ .op = .index });
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(loop_slot) });
                    try chunk.emit(.{ .op = .pop });
                    const collection_first = if (end + 1 < finish and tokens[end + 1].kind == .indent) end + 2 else end + 1;
                    const collection_after = helpers.skipSuite(tokens, end + 1);
                    const collection_breaks = break_targets.items.len;
                    const collection_continues = continue_targets.items.len;
                    try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = collection_breaks, .continues_first = collection_continues });
                    try self.compileLines(chunk, tokens, collection_first, collection_after - 1, names, functions, loops, break_targets, continue_targets);
                    _ = loops.pop();
                    const collection_increment = chunk.code.items.len;
                    for (continue_targets.items[collection_continues..]) |target| chunk.code.items[target].operand = @intCast(collection_increment);
                    continue_targets.shrinkRetainingCapacity(collection_continues);
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(index_slot) });
                    try chunk.emit(.{ .op = .constant, .operand = 1 });
                    try chunk.emit(.{ .op = .add });
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(index_slot) });
                    try chunk.emit(.{ .op = .pop });
                    try chunk.emit(.{ .op = .jump, .operand = @intCast(collection_loop) });
                    chunk.code.items[collection_exit].operand = @intCast(chunk.code.items.len);
                    for (break_targets.items[collection_breaks..]) |target| chunk.code.items[target].operand = @intCast(chunk.code.items.len);
                    break_targets.shrinkRetainingCapacity(collection_breaks);
                    start = collection_after;
                    continue;
                }
                const range = helpers.parseRangeCall(iterable_tokens);
                const empty_tokens = [_]lexer.Token{};
                const initial_tokens = if (range) |parts| if (parts.count == 1) empty_tokens[0..] else parts.args[0] else empty_tokens[0..];
                const limit_tokens = if (range) |parts| if (parts.count == 1) parts.args[0] else parts.args[1] else iterable_tokens;
                const step_tokens = if (range) |parts| if (parts.count == 3) parts.args[2] else empty_tokens[0..] else empty_tokens[0..];
                const literal_limit = limit_tokens.len == 1 and limit_tokens[0].kind == .number;
                const limit_slot = if (literal_limit) blk: {
                    const limit_name = try std.fmt.allocPrint(self.allocator, "__ravi_limit_{d}", .{loop_id});
                    break :blk try helpers.localSlot(names, self.allocator, limit_name);
                } else 0;
                if (initial_tokens.len == 0) try chunk.emit(.{ .op = .constant, .operand = 0 }) else try self.compileRange(chunk, initial_tokens, names, functions);
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(current_slot) });
                try chunk.emit(.{ .op = .pop });
                if (step_tokens.len == 0) try chunk.emit(.{ .op = .constant, .operand = 1 }) else try self.compileRange(chunk, step_tokens, names, functions);
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(step_slot) });
                try chunk.emit(.{ .op = .pop });
                if (literal_limit) {
                    try self.compileRange(chunk, limit_tokens, names, functions);
                    try chunk.emit(.{ .op = .store_local, .operand = @intCast(limit_slot) });
                    try chunk.emit(.{ .op = .pop });
                }
                const loop_start = chunk.code.items.len;
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                if (literal_limit) try chunk.emit(.{ .op = .load_local, .operand = @intCast(limit_slot) }) else try self.compileRange(chunk, limit_tokens, names, functions);
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(step_slot) });
                try chunk.emit(.{ .op = .range_condition });
                const exit_jump = chunk.code.items.len;
                try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                const body_first = if (end + 1 < finish and tokens[end + 1].kind == .indent) end + 2 else end + 1;
                const body_after = helpers.skipSuite(tokens, end + 1);
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(current_slot) });
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(loop_slot) });
                try chunk.emit(.{ .op = .pop });
                const context_start = break_targets.items.len;
                const continue_start = continue_targets.items.len;
                try loops.append(self.allocator, .{ .continue_target = std.math.maxInt(usize), .breaks_first = context_start, .continues_first = continue_start });
                try self.compileLines(chunk, tokens, body_first, body_after - 1, names, functions, loops, break_targets, continue_targets);
                _ = loops.pop();
                const increment_start = chunk.code.items.len;
                for (continue_targets.items[continue_start..]) |target| chunk.code.items[target].operand = @intCast(increment_start);
                continue_targets.shrinkRetainingCapacity(continue_start);
                const packed_range_slots = (@as(i64, @intCast(current_slot)) << 32) | @as(i64, @intCast(step_slot));
                try chunk.emit(.{ .op = .range_step, .operand = packed_range_slots });
                try chunk.emit(.{ .op = .jump, .operand = @intCast(loop_start) });
                chunk.code.items[exit_jump].operand = @intCast(chunk.code.items.len);
                for (break_targets.items[context_start..]) |target| chunk.code.items[target].operand = @intCast(chunk.code.items.len);
                break_targets.shrinkRetainingCapacity(context_start);
                start = body_after;
                continue;
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "raise")) {
                if (start + 1 < end) try self.compileRange(chunk, tokens[start + 1 .. end], names, functions) else try chunk.emit(.{ .op = .constant, .operand = 0 });
                try chunk.emit(.{ .op = .raise_value });
                start = end + 1;
                continue;
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "try")) {
                const colon = helpers.findColon(tokens, start, end) orelse return error.UnsupportedOperator;
                const body_first = if (end + 1 < finish and tokens[end + 1].kind == .indent) end + 2 else end + 1;
                const body_after = helpers.skipSuite(tokens, end + 1);
                const except_line = helpers.skipLineTrivia(tokens, body_after);
                if (except_line >= finish or !self.keyword(tokens[except_line], "except")) return error.UnsupportedOperator;
                _ = colon;
                var except_end = except_line;
                while (except_end < finish and tokens[except_end].kind != .newline and tokens[except_end].kind != .eof) except_end += 1;
                const except_first = if (except_end + 1 < finish and tokens[except_end + 1].kind == .indent) except_end + 2 else except_end + 1;
                const except_after = helpers.skipSuite(tokens, except_end + 1);
                const begin_try = chunk.code.items.len;
                try chunk.emit(.{ .op = .try_begin, .operand = 0 });
                try self.compileLines(chunk, tokens, body_first, body_after - 1, names, functions, loops, break_targets, continue_targets);
                try chunk.emit(.{ .op = .try_end });
                const skip_handler = chunk.code.items.len;
                try chunk.emit(.{ .op = .jump, .operand = 0 });
                chunk.code.items[begin_try].operand = @intCast(chunk.code.items.len);
                try self.compileLines(chunk, tokens, except_first, except_after - 1, names, functions, loops, break_targets, continue_targets);
                const finally_line = helpers.skipLineTrivia(tokens, except_after);
                var final_after = except_after;
                var finally_start: ?usize = null;
                if (finally_line < finish and self.keyword(tokens[finally_line], "finally")) {
                    var finally_end = finally_line;
                    while (finally_end < finish and tokens[finally_end].kind != .newline and tokens[finally_end].kind != .eof) finally_end += 1;
                    const finally_first = if (finally_end + 1 < finish and tokens[finally_end + 1].kind == .indent) finally_end + 2 else finally_end + 1;
                    final_after = helpers.skipSuite(tokens, finally_end + 1);
                    finally_start = chunk.code.items.len;
                    try self.compileLines(chunk, tokens, finally_first, final_after - 1, names, functions, loops, break_targets, continue_targets);
                }
                chunk.code.items[skip_handler].operand = @intCast(finally_start orelse chunk.code.items.len);
                start = final_after;
                continue;
            }
            if (tokens[start].kind == .keyword and (self.keyword(tokens[start], "function") or self.keyword(tokens[start], "else") or self.keyword(tokens[start], "for") or self.keyword(tokens[start], "try") or self.keyword(tokens[start], "except") or self.keyword(tokens[start], "finally"))) {
                if (self.keyword(tokens[start], "function") and self.active_function != null and start + 1 < end and tokens[start + 1].kind == .identifier) {
                    if (helpers.findFunction(functions, tokens[start + 1].lexeme)) |nested_index| {
                        const nested = functions[nested_index];
                        for (nested.captures[0..nested.capture_count]) |capture| {
                            if (helpers.findLocal(names.items, capture)) |slot| {
                                try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                            } else if (helpers.findCapture(self.active_captures[0..self.active_capture_count], capture)) |capture_slot| {
                                try chunk.emit(.{ .op = .load_capture_ref, .operand = @intCast(capture_slot) });
                            } else {
                                return error.InvalidName;
                            }
                        }
                        if (nested.capture_count == 0) {
                            try chunk.emit(.{ .op = .make_function, .operand = @intCast(nested_index) });
                        } else {
                            try chunk.emit(.{ .op = .make_closure, .operand = @intCast(nested_index) });
                        }
                        const local = try helpers.localSlot(names, self.allocator, nested.name);
                        try chunk.emit(.{ .op = .store_local, .operand = @intCast(local) });
                        try chunk.emit(.{ .op = .pop });
                    }
                }
                start = if (self.keyword(tokens[start], "function")) helpers.skipSuite(tokens, end + 1) else end + 1;
                continue;
            }
            var expression_start = start;
            var store: ?usize = null;
            var capture_store: ?usize = null;
            if (tokens[start].kind == .identifier and start + 4 < end and tokens[start + 1].kind == .dot and tokens[start + 2].kind == .identifier and tokens[start + 3].kind == .operator and std.mem.eql(u8, tokens[start + 3].lexeme, "=")) {
                const object_slot = helpers.findLocal(names.items, tokens[start].lexeme) orelse return error.InvalidName;
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(object_slot) });
                try self.compileRange(chunk, tokens[start + 4 .. end], names, functions);
                const property = try chunk.addString(tokens[start + 2].lexeme);
                try chunk.emit(.{ .op = .set_property, .operand = @intCast(property) });
                start = end + 1;
                continue;
            }
            if (tokens[start].kind == .identifier and start + 1 < end and tokens[start + 1].kind == .l_bracket) {
                var close_index = start + 2;
                while (close_index < end and tokens[close_index].kind != .r_bracket) close_index += 1;
                if (close_index + 1 < end and tokens[close_index + 1].kind == .operator and std.mem.eql(u8, tokens[close_index + 1].lexeme, "=")) {
                    const object_slot = helpers.findLocal(names.items, tokens[start].lexeme) orelse return error.InvalidName;
                    try chunk.emit(.{ .op = .load_local, .operand = @intCast(object_slot) });
                    try self.compileRange(chunk, tokens[start + 2 .. close_index], names, functions);
                    try self.compileRange(chunk, tokens[close_index + 2 .. end], names, functions);
                    try chunk.emit(.{ .op = .store_index });
                    start = end + 1;
                    continue;
                }
            }
            if (tokens[start].kind == .identifier) {
                var equals: ?usize = null;
                if (start + 1 < end and tokens[start + 1].kind == .operator and std.mem.eql(u8, tokens[start + 1].lexeme, "=")) {
                    equals = start + 1;
                }
                if (equals == null and start + 1 < end and tokens[start + 1].kind == .colon) {
                    var cursor = start + 2;
                    while (cursor < end) : (cursor += 1) {
                        if (tokens[cursor].kind == .operator and std.mem.eql(u8, tokens[cursor].lexeme, "=")) {
                            equals = cursor;
                            break;
                        }
                    }
                }
                if (equals) |position| {
                    if (helpers.findCapture(self.active_captures[0..self.active_capture_count], tokens[start].lexeme)) |capture| {
                        capture_store = capture;
                    } else {
                        store = try helpers.localSlot(names, self.allocator, tokens[start].lexeme);
                    }
                    expression_start = position + 1;
                }
            } else if (tokens[start].kind == .keyword and (self.keyword(tokens[start], "return") or self.keyword(tokens[start], "yield"))) expression_start += 1;
            if (expression_start < end) try self.compileRange(chunk, tokens[expression_start..end], names, functions);
            if (store) |slot| {
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(slot) });
                try chunk.emit(.{ .op = .pop });
            }
            if (capture_store) |capture| {
                try chunk.emit(.{ .op = .store_capture, .operand = @intCast(capture) });
                try chunk.emit(.{ .op = .pop });
            }
            if (tokens[start].kind == .keyword and self.keyword(tokens[start], "return")) {
                try chunk.emit(.{ .op = .return_value });
            } else if (tokens[start].kind == .keyword and (self.keyword(tokens[start], "yield") or self.keyword(tokens[start], "taru"))) {
                try chunk.emit(.{ .op = .suspend_point, .operand = @intCast(tokens[start].line) });
            }
            start = end + 1;
        }
    }

    pub fn compileRange(self: *Compiler, chunk: *bytecode.Chunk, tokens: []const lexer.Token, names: *std.ArrayListUnmanaged([]const u8), functions: []const FunctionDecl) CompileError!void {
        if (self.findLogical(tokens, "or")) |operator| {
            try self.compileRange(chunk, tokens[0..operator], names, functions);
            const evaluate_right = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
            try chunk.emit(.{ .op = .constant, .operand = 1 });
            const finish = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump, .operand = 0 });
            chunk.code.items[evaluate_right].operand = @intCast(chunk.code.items.len);
            try self.compileRange(chunk, tokens[operator + 1 ..], names, functions);
            try chunk.emit(.{ .op = .not });
            try chunk.emit(.{ .op = .not });
            chunk.code.items[finish].operand = @intCast(chunk.code.items.len);
            return;
        }
        if (self.findLogical(tokens, "and")) |operator| {
            try self.compileRange(chunk, tokens[0..operator], names, functions);
            const false_jump = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
            try self.compileRange(chunk, tokens[operator + 1 ..], names, functions);
            try chunk.emit(.{ .op = .not });
            try chunk.emit(.{ .op = .not });
            const finish = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump, .operand = 0 });
            chunk.code.items[false_jump].operand = @intCast(chunk.code.items.len);
            try chunk.emit(.{ .op = .constant, .operand = 0 });
            chunk.code.items[finish].operand = @intCast(chunk.code.items.len);
            return;
        }
        if (try self.compileChainedComparison(chunk, tokens, names, functions)) return;
        if (tokens.len != 0 and tokens[0].kind == .keyword and self.keyword(tokens[0], "not")) {
            const inner = if (tokens.len >= 3 and tokens[1].kind == .l_paren and tokens[tokens.len - 1].kind == .r_paren) tokens[2 .. tokens.len - 1] else tokens[1..];
            try self.compileRange(chunk, inner, names, functions);
            try chunk.emit(.{ .op = .not });
            return;
        }
        if (tokens.len > 1 and tokens[0].kind == .operator and std.mem.eql(u8, tokens[0].lexeme, "-")) {
            try self.compileRange(chunk, tokens[1..], names, functions);
            try chunk.emit(.{ .op = .negate });
            return;
        }
        var operators: std.ArrayListUnmanaged(bytecode.OpCode) = .empty;
        defer operators.deinit(self.allocator);
        var expect = true;
        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const token = tokens[i];
            self.last_location = helpers.sourceLocation(token);
            chunk.setSourceLocation(self.last_location);
            switch (token.kind) {
                .number => {
                    if (!expect) continue;
                    const value = std.fmt.parseInt(i64, token.lexeme, 10) catch return error.InvalidNumber;
                    try chunk.emit(.{ .op = .constant, .operand = value });
                    expect = false;
                },
                .string => {
                    if (!expect) continue;
                    const string_index = try chunk.addString(token.lexeme);
                    try chunk.emit(.{ .op = .make_string, .operand = @intCast(string_index) });
                    expect = false;
                },
                .identifier => {
                    if (!expect) continue;
                    if (i + 2 < tokens.len and tokens[i + 1].kind == .dot and tokens[i + 2].kind == .identifier and (i + 3 >= tokens.len or tokens[i + 3].kind != .l_paren)) {
                        const slot = helpers.findLocal(names.items, token.lexeme) orelse return error.InvalidName;
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                        const property = try chunk.addString(tokens[i + 2].lexeme);
                        try chunk.emit(.{ .op = .get_property, .operand = @intCast(property) });
                        i += 2;
                        expect = false;
                    } else if (i + 3 < tokens.len and tokens[i + 1].kind == .dot and tokens[i + 2].kind == .identifier and tokens[i + 3].kind == .l_paren) {
                        const method = tokens[i + 2].lexeme;
                        const slot = helpers.findLocal(names.items, token.lexeme) orelse return error.InvalidName;
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                        var close = i + 4;
                        while (close < tokens.len and tokens[close].kind != .r_paren) : (close += 1) {}
                        if (close >= tokens.len) return error.UnterminatedCall;
                        const is_append = builtins.method(self.language, method, "append", "serisu");
                        const is_insert = builtins.method(self.language, method, "insert", "haku");
                        const is_remove = builtins.method(self.language, method, "remove", "tegi");
                        const is_contains = builtins.method(self.language, method, "contains", "olagide");
                        const is_clear = builtins.method(self.language, method, "clear", "khaali");
                        const is_pop = builtins.method(self.language, method, "pop", "kithu");
                        const is_count = builtins.method(self.language, method, "count", "enisu");
                        const is_length = builtins.method(self.language, method, "length", "gatra");
                        const is_lower = builtins.method(self.language, method, "lower", "chikku");
                        const is_upper = builtins.method(self.language, method, "upper", "doddu");
                        const is_strip = builtins.method(self.language, method, "strip", "kadi");
                        const is_find = builtins.method(self.language, method, "find", "huduk");
                        const is_replace = builtins.method(self.language, method, "replace", "badla");
                        const is_split = builtins.method(self.language, method, "split", "ode");
                        const is_join = builtins.method(self.language, method, "join", "jote");
                        const is_reverse = builtins.method(self.language, method, "reverse", "ultha");
                        const is_sort = builtins.method(self.language, method, "sort", "jodisu");
                        const is_get = builtins.method(self.language, method, "get", "tago");
                        const is_update = builtins.method(self.language, method, "update", "badala");
                        const is_dict_remove = builtins.method(self.language, method, "pop", "tegi");
                        const is_keys = builtins.method(self.language, method, "keys", "kili");
                        const is_values = builtins.method(self.language, method, "values", "bele");
                        const is_items = builtins.method(self.language, method, "items", "jodi");
                        const is_union = builtins.method(self.language, method, "union", "koodu");
                        const is_intersection = builtins.method(self.language, method, "intersection", "ondu");
                        const is_difference = builtins.method(self.language, method, "difference", "bere");
                        const is_dict_contains = builtins.method(self.language, method, "contains", "olagide");
                        if (is_append or is_contains or is_insert or is_remove or is_get or is_update or is_dict_remove or is_union or is_intersection or is_difference or is_find or is_replace or is_split or is_join) {
                            if (close == i + 4) return error.InvalidFunction;
                            try self.compileRange(chunk, tokens[i + 4 .. close], names, functions);
                        }
                        if (is_append) try chunk.emit(.{ .op = .append_collection }) else if (is_insert) try chunk.emit(.{ .op = .insert_collection }) else if (is_remove) try chunk.emit(.{ .op = .remove_collection }) else if (is_contains) try chunk.emit(.{ .op = .contains_collection }) else if (is_clear) try chunk.emit(.{ .op = .clear_collection }) else if (is_dict_remove and close > i + 4) try chunk.emit(.{ .op = .dict_remove }) else if (is_pop) try chunk.emit(.{ .op = .pop_collection }) else if (is_count) try chunk.emit(.{ .op = .count_collection }) else if (is_length) try chunk.emit(.{ .op = .length }) else if (is_lower) try chunk.emit(.{ .op = .string_lower }) else if (is_upper) try chunk.emit(.{ .op = .string_upper }) else if (is_strip) try chunk.emit(.{ .op = .string_strip }) else if (is_find) try chunk.emit(.{ .op = .string_find }) else if (is_replace) try chunk.emit(.{ .op = .string_replace }) else if (is_split) try chunk.emit(.{ .op = .string_split }) else if (is_join) try chunk.emit(.{ .op = .string_join }) else if (is_reverse) try chunk.emit(.{ .op = .reverse_collection }) else if (is_sort) try chunk.emit(.{ .op = .sort_collection }) else if (is_get) try chunk.emit(.{ .op = .dict_get }) else if (is_update) try chunk.emit(.{ .op = .dict_put }) else if (is_keys) try chunk.emit(.{ .op = .dict_keys }) else if (is_values) try chunk.emit(.{ .op = .dict_values }) else if (is_items) try chunk.emit(.{ .op = .dict_items }) else if (is_union) try chunk.emit(.{ .op = .set_union }) else if (is_intersection) try chunk.emit(.{ .op = .set_intersection }) else if (is_difference) try chunk.emit(.{ .op = .set_difference }) else if (is_dict_remove) try chunk.emit(.{ .op = .dict_remove }) else if (is_dict_contains) try chunk.emit(.{ .op = .dict_contains }) else if (helpers.findFunction(functions, method)) |function_index| {
                            if (functions[function_index].visibility == .private and self.active_function == null) return error.PrivateAccess;
                            try call_codegen.emit(self, chunk, tokens[i + 4 .. close], functions[function_index], names, functions);
                            try chunk.emit(.{ .op = .call_method, .operand = @intCast(function_index) });
                        } else return error.InvalidFunction;
                        i = close;
                        expect = false;
                    } else if (i + 1 < tokens.len and tokens[i + 1].kind == .l_paren) {
                        var close = i + 2;
                        var nesting: usize = 1;
                        while (close < tokens.len and nesting != 0) : (close += 1) {
                            if (tokens[close].kind == .l_paren) nesting += 1 else if (tokens[close].kind == .r_paren) nesting -= 1;
                        }
                        if (nesting != 0) return error.UnterminatedCall;
                        close -= 1;
                        if (builtins.isType(self.language, token.lexeme)) {
                            if (close == i + 2) return error.InvalidFunction;
                            try self.compileRange(chunk, tokens[i + 2 .. close], names, functions);
                            try chunk.emit(.{ .op = .type_query });
                        } else if (builtins.isPrint(self.language, token.lexeme)) {
                            if (close > i + 2) try self.compileRange(chunk, tokens[i + 2 .. close], names, functions);
                            try chunk.emit(.{ .op = .print });
                        } else if (helpers.findLocal(names.items, token.lexeme)) |slot| {
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                            if (close > i + 2) try self.compileRange(chunk, tokens[i + 2 .. close], names, functions);
                            try chunk.emit(.{ .op = .call_value, .operand = @intCast(helpers.argumentCount(tokens[i + 2 .. close])) });
                        } else if (helpers.findFunction(functions, token.lexeme)) |function_index| {
                            try call_codegen.emit(self, chunk, tokens[i + 2 .. close], functions[function_index], names, functions);
                            try chunk.emit(.{ .op = .call, .operand = @intCast(function_index) });
                        } else if (self.findClass(token.lexeme)) |class_index| {
                            try chunk.emit(.{ .op = .make_instance, .operand = @intCast(class_index) });
                            const constructor = helpers.findFunction(functions, "huttu") orelse helpers.findFunction(functions, "init");
                            if (constructor) |function_index| {
                                try chunk.emit(.{ .op = .dup });
                                try call_codegen.emit(self, chunk, tokens[i + 2 .. close], functions[function_index], names, functions);
                                try chunk.emit(.{ .op = .call_method, .operand = @intCast(function_index) });
                                try chunk.emit(.{ .op = .pop });
                            } else if (close > i + 2) return error.InvalidFunction;
                        } else if (std.mem.eql(u8, token.lexeme, "add") or std.mem.eql(u8, token.lexeme, "sub") or std.mem.eql(u8, token.lexeme, "mul") or std.mem.eql(u8, token.lexeme, "div") or std.mem.eql(u8, token.lexeme, "mod")) {
                            if (close > i + 2) try self.compileRange(chunk, tokens[i + 2 .. close], names, functions);
                            const op: bytecode.OpCode = if (std.mem.eql(u8, token.lexeme, "add")) .add else if (std.mem.eql(u8, token.lexeme, "sub")) .subtract else if (std.mem.eql(u8, token.lexeme, "mul")) .multiply else if (std.mem.eql(u8, token.lexeme, "div")) .divide else .modulo;
                            try chunk.emit(.{ .op = op });
                        } else return error.InvalidFunction;
                        i = close;
                        expect = false;
                    } else if (i + 1 < tokens.len and tokens[i + 1].kind == .l_bracket) {
                        const slot = helpers.findLocal(names.items, token.lexeme) orelse return error.InvalidName;
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                        var close = i + 2;
                        while (close < tokens.len and tokens[close].kind != .r_bracket) close += 1;
                        if (close >= tokens.len) return error.UnterminatedCall;
                        var colon: ?usize = null;
                        for (i + 2..close) |candidate| if (tokens[candidate].kind == .colon) {
                            colon = candidate;
                            break;
                        };
                        if (colon) |separator| {
                            if (separator == i + 2) try chunk.emit(.{ .op = .constant, .operand = -1 }) else try self.compileRange(chunk, tokens[i + 2 .. separator], names, functions);
                            if (separator + 1 == close) try chunk.emit(.{ .op = .constant, .operand = -1 }) else try self.compileRange(chunk, tokens[separator + 1 .. close], names, functions);
                            try chunk.emit(.{ .op = .slice });
                        } else {
                            try self.compileRange(chunk, tokens[i + 2 .. close], names, functions);
                            try chunk.emit(.{ .op = .index });
                        }
                        i = close;
                        expect = false;
                    } else {
                        if (helpers.findLocal(names.items, token.lexeme)) |slot| {
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                        } else if (helpers.findCapture(self.active_captures[0..self.active_capture_count], token.lexeme)) |capture| {
                            try chunk.emit(.{ .op = .load_capture, .operand = @intCast(capture) });
                        } else if (helpers.findFunction(functions, token.lexeme)) |function_index| {
                            try chunk.emit(.{ .op = .make_function, .operand = @intCast(function_index) });
                        } else {
                            // Variable assignment/global fallback
                            try names.append(self.allocator, token.lexeme);
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(names.items.len - 1) });
                        }
                        expect = false;
                    }
                },
                .l_bracket => {
                    if (!expect) continue;
                    var close = i + 1;
                    var nesting: usize = 1;
                    while (close < tokens.len and nesting != 0) : (close += 1) {
                        if (tokens[close].kind == .l_bracket) nesting += 1 else if (tokens[close].kind == .r_bracket) nesting -= 1;
                    }
                    if (nesting != 0) return error.UnterminatedCall;
                    close -= 1;
                    var count: usize = 0;
                    var item_start = i + 1;
                    var cursor = item_start;
                    while (cursor <= close) {
                        if (cursor == close or tokens[cursor].kind == .comma) {
                            if (cursor > item_start) {
                                try self.compileRange(chunk, tokens[item_start..cursor], names, functions);
                                count += 1;
                            }
                            item_start = cursor + 1;
                        }
                        cursor += 1;
                    }
                    try chunk.emit(.{ .op = .make_array, .operand = @intCast(count) });
                    i = close;
                    expect = false;
                },
                .l_paren => {
                    if (!expect) continue;
                    var close = i + 1;
                    var nesting: usize = 1;
                    var has_comma = false;
                    while (close < tokens.len and nesting != 0) : (close += 1) {
                        if (tokens[close].kind == .l_paren) nesting += 1 else if (tokens[close].kind == .r_paren) nesting -= 1 else if (tokens[close].kind == .comma and nesting == 1) has_comma = true;
                    }
                    if (nesting != 0) return error.UnterminatedCall;
                    close -= 1;
                    if (has_comma) {
                        var count: usize = 0;
                        var item_start = i + 1;
                        var cursor = item_start;
                        while (cursor <= close) {
                            if (cursor == close or tokens[cursor].kind == .comma) {
                                if (cursor > item_start) {
                                    try self.compileRange(chunk, tokens[item_start..cursor], names, functions);
                                    count += 1;
                                }
                                item_start = cursor + 1;
                            }
                            cursor += 1;
                        }
                        try chunk.emit(.{ .op = .make_tuple, .operand = @intCast(count) });
                        i = close;
                        expect = false;
                    }
                },
                .l_brace => {
                    if (!expect) continue;
                    var close = i + 1;
                    var nesting: usize = 1;
                    var is_dict = false;
                    while (close < tokens.len and nesting != 0) : (close += 1) {
                        if (tokens[close].kind == .l_brace) nesting += 1 else if (tokens[close].kind == .r_brace) nesting -= 1 else if (tokens[close].kind == .colon and nesting == 1) is_dict = true;
                    }
                    if (nesting != 0) return error.UnterminatedCall;
                    close -= 1;
                    var count: usize = 0;
                    var item_start = i + 1;
                    var cursor = item_start;
                    while (cursor <= close) {
                        if (cursor == close or tokens[cursor].kind == .comma) {
                            if (cursor > item_start) {
                                var colon: ?usize = null;
                                for (item_start..cursor) |p| if (tokens[p].kind == .colon) {
                                    colon = p;
                                    break;
                                };
                                if (is_dict) {
                                    const c = colon orelse return error.UnsupportedOperator;
                                    try self.compileRange(chunk, tokens[item_start..c], names, functions);
                                    try self.compileRange(chunk, tokens[c + 1 .. cursor], names, functions);
                                } else try self.compileRange(chunk, tokens[item_start..cursor], names, functions);
                                count += 1;
                            }
                            item_start = cursor + 1;
                        }
                        cursor += 1;
                    }
                    if (is_dict) try chunk.emit(.{ .op = .make_dict, .operand = @intCast(count) }) else try chunk.emit(.{ .op = .make_set, .operand = @intCast(count) });
                    i = close;
                    expect = false;
                },
                .keyword => {
                    const canonical = config.keywordCanonicalFor(self.language, token.lexeme) orelse token.lexeme;
                    if (std.mem.eql(u8, canonical, "super") and i + 4 < tokens.len and tokens[i + 1].kind == .dot and tokens[i + 2].kind == .identifier and tokens[i + 3].kind == .l_paren) {
                        const class_index = self.active_class orelse return error.InvalidFunction;
                        const base_name = self.class_bases[class_index] orelse return error.InvalidFunction;
                        const base_index = self.findClass(base_name) orelse return error.InvalidFunction;
                        const method_name = tokens[i + 2].lexeme;
                        var function_index: ?usize = null;
                        for (functions, 0..) |function, candidate| {
                            if (!function.method or !std.mem.eql(u8, function.name, method_name)) continue;
                            if (function.body_first >= self.class_body_first[base_index] and function.body_first < self.class_body_end[base_index]) {
                                function_index = candidate;
                                break;
                            }
                        }
                        const resolved = function_index orelse return error.InvalidFunction;
                        const receiver = helpers.findLocal(names.items, "tanna") orelse return error.InvalidName;
                        try chunk.emit(.{ .op = .load_local, .operand = @intCast(receiver) });
                        var close = i + 4;
                        var nesting: usize = 1;
                        while (close < tokens.len and nesting != 0) : (close += 1) {
                            if (tokens[close].kind == .l_paren) nesting += 1 else if (tokens[close].kind == .r_paren) nesting -= 1;
                        }
                        if (nesting != 0) return error.UnterminatedCall;
                        close -= 1;
                        try call_codegen.emit(self, chunk, tokens[i + 4 .. close], functions[resolved], names, functions);
                        try chunk.emit(.{ .op = .call_super, .operand = @intCast(resolved) });
                        i = close;
                        expect = false;
                    } else if (std.mem.eql(u8, canonical, "function") and i + 1 < tokens.len and tokens[i + 1].kind == .l_paren) {
                        const lambda = helpers.firstLambda(functions) orelse return error.InvalidFunction;
                        const lambda_index = helpers.findFunction(functions, lambda.name) orelse return error.InvalidFunction;
                        for (lambda.captures[0..lambda.capture_count]) |capture_name| {
                            const slot = helpers.findLocal(names.items, capture_name) orelse return error.InvalidName;
                            try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
                        }
                        if (lambda.capture_count == 0) try chunk.emit(.{ .op = .make_function, .operand = @intCast(lambda_index) }) else try chunk.emit(.{ .op = .make_closure, .operand = @intCast(lambda_index) });
                        var end = i + 2;
                        while (end < tokens.len and tokens[end].kind != .fat_arrow) end += 1;
                        if (end >= tokens.len) return error.InvalidFunction;
                        while (end < tokens.len and tokens[end].kind != .newline) end += 1;
                        i = if (end > 0) end - 1 else end;
                        expect = false;
                    } else if (std.mem.eql(u8, canonical, "true") or std.mem.eql(u8, canonical, "false")) {
                        try chunk.emit(.{ .op = .constant, .operand = if (std.mem.eql(u8, canonical, "true")) 1 else 0 });
                        expect = false;
                    } else if (std.mem.eql(u8, canonical, "not")) {
                        try self.compileRange(chunk, tokens[i + 1 ..], names, functions);
                        try chunk.emit(.{ .op = .not });
                        while (operators.items.len > 0) try chunk.emit(.{ .op = operators.pop().? });
                        return;
                    } else if (std.mem.eql(u8, canonical, "and") or std.mem.eql(u8, canonical, "or")) {
                        const op: bytecode.OpCode = if (std.mem.eql(u8, canonical, "and")) .logic_and else .logic_or;
                        while (operators.items.len > 0 and expression_runtime.precedence(operators.items[operators.items.len - 1]) >= expression_runtime.precedence(op)) try chunk.emit(.{ .op = operators.pop().? });
                        try operators.append(self.allocator, op);
                        expect = true;
                    }
                },
                .operator => {
                    if (expect) {
                        if (std.mem.eql(u8, token.lexeme, "-")) {
                            try self.compileRange(chunk, tokens[i + 1 ..], names, functions);
                            try chunk.emit(.{ .op = .negate });
                            while (operators.items.len > 0) try chunk.emit(.{ .op = operators.pop().? });
                            return;
                        }
                    } else {
                        const op = expression_runtime.operator(token.lexeme) orelse return error.UnsupportedOperator;
                        while (operators.items.len > 0 and expression_runtime.precedence(operators.items[operators.items.len - 1]) >= expression_runtime.precedence(op)) try chunk.emit(.{ .op = operators.pop().? });
                        try operators.append(self.allocator, op);
                        expect = true;
                    }
                },
                .comma => expect = true,
                else => {},
            }
        }
        while (operators.items.len > 0) try chunk.emit(.{ .op = operators.pop().? });
    }

    fn findLogical(self: *const Compiler, tokens: []const lexer.Token, canonical: []const u8) ?usize {
        var depth: usize = 0;
        for (tokens, 0..) |token, index| {
            switch (token.kind) {
                .l_paren, .l_bracket, .l_brace => depth += 1,
                .r_paren, .r_bracket, .r_brace => if (depth > 0) {
                    depth -= 1;
                },
                .keyword => if (depth == 0 and self.keyword(token, canonical)) return index,
                else => {},
            }
        }
        return null;
    }

    fn compileChainedComparison(self: *Compiler, chunk: *bytecode.Chunk, tokens: []const lexer.Token, names: *std.ArrayListUnmanaged([]const u8), functions: []const FunctionDecl) CompileError!bool {
        var operators: [16]usize = undefined;
        var count: usize = 0;
        var depth: usize = 0;
        for (tokens, 0..) |token, index| {
            switch (token.kind) {
                .l_paren, .l_bracket, .l_brace => depth += 1,
                .r_paren, .r_bracket, .r_brace => if (depth > 0) {
                    depth -= 1;
                },
                .operator => if (depth == 0 and helpers.comparisonOpcode(token.lexeme) != null) {
                    if (count == operators.len) return error.UnsupportedOperator;
                    operators[count] = index;
                    count += 1;
                },
                else => {},
            }
        }
        if (count < 2) return false;

        const left_slot = try helpers.localSlot(names, self.allocator, "__ravi_chain_left");
        const right_slot = try helpers.localSlot(names, self.allocator, "__ravi_chain_right");
        try self.compileRange(chunk, tokens[0..operators[0]], names, functions);
        try chunk.emit(.{ .op = .store_local, .operand = @intCast(left_slot) });
        try chunk.emit(.{ .op = .pop });
        var false_jumps: [16]usize = undefined;
        var false_count: usize = 0;

        for (operators[0..count], 0..) |operator_index, comparison| {
            const right_end = if (comparison + 1 < count) operators[comparison + 1] else tokens.len;
            if (comparison + 1 < count) {
                try self.compileRange(chunk, tokens[operator_index + 1 .. right_end], names, functions);
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(right_slot) });
                try chunk.emit(.{ .op = .pop });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(left_slot) });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(right_slot) });
            } else {
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(left_slot) });
                try self.compileRange(chunk, tokens[operator_index + 1 .. right_end], names, functions);
            }
            try chunk.emit(.{ .op = helpers.comparisonOpcode(tokens[operator_index].lexeme).? });
            if (comparison + 1 < count) {
                false_jumps[false_count] = chunk.code.items.len;
                false_count += 1;
                try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(right_slot) });
                try chunk.emit(.{ .op = .store_local, .operand = @intCast(left_slot) });
                try chunk.emit(.{ .op = .pop });
            }
        }
        const finish = chunk.code.items.len;
        try chunk.emit(.{ .op = .jump, .operand = 0 });
        const false_target = chunk.code.items.len;
        try chunk.emit(.{ .op = .constant, .operand = 0 });
        const end = chunk.code.items.len;
        chunk.code.items[finish].operand = @intCast(end);
        for (false_jumps[0..false_count]) |jump| chunk.code.items[jump].operand = @intCast(false_target);
        return true;
    }

    fn findClass(self: *const Compiler, name: []const u8) ?usize {
        for (self.class_names[0..self.class_count], 0..) |class_name, index| {
            if (std.mem.eql(u8, class_name, name)) return index;
        }
        return null;
    }

    pub fn keyword(self: *const Compiler, token: lexer.Token, canonical: []const u8) bool {
        return std.mem.eql(u8, config.keywordCanonicalFor(self.language, token.lexeme) orelse token.lexeme, canonical);
    }
    pub fn emitParameterGuard(self: *Compiler, chunk: *bytecode.Chunk, annotation: ?[]const u8) CompileError!void {
        _ = self;
        if (annotation) |type_name| {
            if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer")) try chunk.emit(.{ .op = .guard_integer }) else if (std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean")) try chunk.emit(.{ .op = .guard_boolean }) else if (std.mem.eql(u8, type_name, "string")) try chunk.emit(.{ .op = .guard_string });
        }
    }
};
