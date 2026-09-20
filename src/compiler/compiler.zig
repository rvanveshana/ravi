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
        defer {
            for (self.ast_state.generated_names.items) |name| self.allocator.free(name);
            self.ast_state.generated_names.deinit(self.allocator);
            self.ast_state.generated_names = .empty;
        }
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
            for (chunk.code.items[chunk.functions.items[function_index].entry..]) |instruction| {
                if (instruction.op == .suspend_point) chunk.functions.items[function_index].suspension_count += 1;
            }
            chunk.functions.items[function_index].resumable = chunk.functions.items[function_index].suspension_count != 0;
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

    pub fn compileAstFinalizers(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, names: *std.ArrayListUnmanaged([]const u8), loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        return ast_statements.finalizers(CompileError, self, chunk, module, names, loops, break_targets);
    }

    fn compileAstTopLevel(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, names: *std.ArrayListUnmanaged([]const u8), function_statements: *const std.ArrayListUnmanaged(usize), loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        return ast_statements.topLevel(CompileError, self, chunk, module, names, function_statements, loops, break_targets);
    }

    pub fn compileAstStatements(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, first: usize, count: usize, names: *std.ArrayListUnmanaged([]const u8), discard_expression: bool, loops: *std.ArrayListUnmanaged(AstLoopContext), break_targets: *std.ArrayListUnmanaged(usize)) CompileError!void {
        return @import("ast_statement_lowering.zig").lower(CompileError, self, chunk, module, first, count, names, discard_expression, loops, break_targets);
    }

    pub fn compileAstExpression(self: *Compiler, chunk: *bytecode.Chunk, module: *const ast.Module, expression_id: ast.ExprId, names: *std.ArrayListUnmanaged([]const u8)) CompileError!void {
        return ast_compiler.expression(CompileError, self, chunk, module, expression_id, names);
    }
};
