const std = @import("std");
const ast = @import("ravi_ast");
const loader_mod = @import("ravi_loader");

/// Links ASTs, never source text. Each binding is qualified by module identity;
/// imported names refer to the dependency's binding, not a global text namespace.
pub const Linker = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn deinit(self: *Linker) void {
        for (self.names.items) |name| self.allocator.free(name);
        self.names.deinit(self.allocator);
    }

    fn qualify(self: *Linker, id: usize, name: []const u8) ![]const u8 {
        const qualified = try std.fmt.allocPrint(self.allocator, "@m{d}:{s}", .{ id, name });
        errdefer self.allocator.free(qualified);
        try self.names.append(self.allocator, qualified);
        return qualified;
    }

    fn declare(self: *Linker, names: *std.StringHashMap([]const u8), id: usize, name: []const u8) !void {
        if (!names.contains(name)) try names.put(name, try self.qualify(id, name));
    }

    pub fn link(self: *Linker, loader: *const loader_mod.Loader, order: anytype) !ast.Module {
        var result = ast.Module{ .allocator = self.allocator };
        errdefer result.deinit();
        for (order) |id| {
            const loaded = loader.module(id) orelse return error.InvalidModule;
            const source = &loaded.syntax;
            const module_id = @intFromEnum(id);
            var names = std.StringHashMap([]const u8).init(self.allocator);
            defer names.deinit();
            for (source.parameters.items) |parameter| try self.declare(&names, module_id, parameter.name);
            for (source.statements.items) |statement| switch (statement.kind) {
                .function => |function| try self.declare(&names, module_id, function.name),
                .class_decl => |class| try self.declare(&names, module_id, class.name),
                .control => |control| if (control.target) |target| try self.declare(&names, module_id, target),
                .try_stmt => |value| if (value.except_binding) |binding| try self.declare(&names, module_id, binding),
                .context => |context| if (context.binding) |binding| try self.declare(&names, module_id, binding),
                else => {},
            };
            for (source.expressions.items) |expression| if (expression.kind == .assignment and expression.kind.assignment.target == null) {
                try self.declare(&names, module_id, expression.kind.assignment.name);
            };
            var locals = std.StringHashMap([]const u8).init(self.allocator);
            defer locals.deinit();
            var name_iterator = names.iterator();
            while (name_iterator.next()) |entry| try locals.put(entry.key_ptr.*, entry.value_ptr.*);
            var imports = std.StringHashMap(void).init(self.allocator);
            defer imports.deinit();
            var import_index: usize = 0;
            for (source.statements.items) |statement| if (statement.kind == .import) {
                if (import_index >= loaded.imports.items.len) return error.InvalidModule;
                const dependency = loaded.imports.items[import_index];
                import_index += 1;
                const declaration = statement.kind.import;
                for (source.import_names.items[declaration.names_first .. declaration.names_first + declaration.names_count]) |name| {
                    if (imports.contains(name)) return error.DuplicateDeclaration;
                    for (loader.graph.moduleExports(id)) |symbol| if (std.mem.eql(u8, symbol.name, name)) return error.DuplicateDeclaration;
                    try imports.put(name, {});
                    try names.put(name, try self.qualify(@intFromEnum(dependency), name));
                }
            };
            const offsets = Offsets{
                .expression = @intCast(result.expressions.items.len),
                .statement = result.statements.items.len,
                .collection = result.collection_items.items.len,
                .format = result.format_args.items.len,
                .argument = result.call_args.items.len,
                .keyword = result.call_keywords.items.len,
                .parameter = result.parameters.items.len,
                .decorator = result.decorators.items.len,
            };
            for (source.expressions.items) |original| {
                var expression = original;
                expression.language = loaded.language;
                expression.span.source_id = @intCast(module_id);
                if (expression.kind == .name and shadowed(source, original.span, expression.kind.name)) {
                    expression.kind.name = renamed(&locals, expression.kind.name);
                }
                if (expression.kind == .assignment and shadowed(source, original.span, expression.kind.assignment.name)) expression.kind.assignment.name = renamed(&locals, expression.kind.assignment.name);
                relocateExpression(&expression, offsets, &names);
                try result.expressions.append(self.allocator, expression);
            }
            for (source.statements.items, 0..) |original, index| {
                var statement = original;
                statement.language = loaded.language;
                statement.span.source_id = @intCast(module_id);
                if (statement.kind == .function and isMethod(source, index)) statement.kind.function.method_name = statement.kind.function.name;
                relocateStatement(&statement, offsets, &locals, &names);
                try result.statements.append(self.allocator, statement);
            }
            for (source.parameters.items) |original| {
                var parameter = original;
                parameter.name = renamed(&locals, parameter.name);
                parameter.span.source_id = @intCast(module_id);
                try result.parameters.append(self.allocator, parameter);
            }
            for (source.collection_items.items) |id_value| try result.collection_items.append(self.allocator, id_value + offsets.expression);
            for (source.format_args.items) |id_value| try result.format_args.append(self.allocator, id_value + offsets.expression);
            for (source.call_args.items) |id_value| try result.call_args.append(self.allocator, id_value + offsets.expression);
            try result.call_keywords.appendSlice(self.allocator, source.call_keywords.items);
            try result.decorators.appendSlice(self.allocator, source.decorators.items);
        }
        return result;
    }
};

const Offsets = struct { expression: u32, statement: usize, collection: usize, format: usize, argument: usize, keyword: usize, parameter: usize, decorator: usize };
fn renamed(names: *const std.StringHashMap([]const u8), name: []const u8) []const u8 {
    return names.get(name) orelse name;
}
fn isMethod(module: *const ast.Module, index: usize) bool {
    for (module.statements.items) |statement| if (statement.kind == .class_decl) {
        const class = statement.kind.class_decl;
        if (index >= class.body_first and index < class.body_first + class.body_count) return true;
    };
    return false;
}

fn relocateExpression(expression: *ast.Expr, o: Offsets, names: *const std.StringHashMap([]const u8)) void {
    switch (expression.kind) {
        .name => |*name| name.* = renamed(names, name.*),
        .formatted_string => |*v| v.first_arg += o.format,
        .spawn, .wait => |*id| id.* += o.expression,
        .member => |*v| v.object += o.expression,
        .unary => |*v| v.operand += o.expression,
        .binary => |*v| {
            v.left += o.expression;
            v.right += o.expression;
        },
        .call => |*v| {
            v.callee += o.expression;
            v.first_arg += o.argument;
            v.keyword_first += o.keyword;
        },
        .assignment => |*v| {
            v.name = renamed(names, v.name);
            v.value += o.expression;
            if (v.target) |*target| target.* += o.expression;
        },
        .lambda => |*v| {
            v.params_first += o.parameter;
            v.body += o.expression;
        },
        inline .array, .tuple, .set, .map => |*v| v.first += o.collection,
        .index => |*v| {
            v.object += o.expression;
            v.index += o.expression;
        },
        .slice => |*v| {
            v.object += o.expression;
            if (v.start) |*id| id.* += o.expression;
            if (v.end) |*id| id.* += o.expression;
        },
        else => {},
    }
}

fn relocateStatement(statement: *ast.Stmt, o: Offsets, names: *const std.StringHashMap([]const u8), globals: *const std.StringHashMap([]const u8)) void {
    switch (statement.kind) {
        .import => statement.kind = .{ .transfer = "pass" },
        .expression => |*id| id.* += o.expression,
        .return_stmt, .yield_stmt, .raise_stmt => |*v| {
            if (v.*) |*id| id.* += o.expression;
        },
        .function => |*v| {
            v.name = renamed(names, v.name);
            v.params_first += o.parameter;
            v.body_first += o.statement;
            v.decorators_first += o.decorator;
        },
        .class_decl => |*v| {
            v.name = renamed(names, v.name);
            if (v.base) |*base| base.* = renamed(globals, base.*);
            v.body_first += o.statement;
        },
        .control => |*v| {
            if (v.condition) |*id| id.* += o.expression;
            if (v.iterable) |*id| id.* += o.expression;
            if (v.target) |*target| target.* = renamed(names, target.*);
            v.body_first += o.statement;
            v.else_first += o.statement;
        },
        .try_stmt => |*v| {
            v.body_first += o.statement;
            v.except_first += o.statement;
            v.finally_first += o.statement;
            if (v.except_binding) |*binding| binding.* = renamed(names, binding.*);
            if (v.except_match) |*id| id.* += o.expression;
            if (v.except_type) |*name| name.* = renamed(names, name.*);
        },
        .context => |*v| {
            v.value += o.expression;
            if (v.binding) |*binding| binding.* = renamed(names, binding.*);
        },
        else => {},
    }
}

fn shadowed(module: *const ast.Module, span: ast.Span, name: []const u8) bool {
    for (module.expressions.items) |expression| if (expression.kind == .lambda and span.first >= expression.span.first and span.last <= expression.span.last) {
        const lambda = expression.kind.lambda;
        for (module.parameters.items[lambda.params_first .. lambda.params_first + lambda.params_count]) |parameter| if (std.mem.eql(u8, parameter.name, name)) return true;
    };
    for (module.statements.items) |statement| if (statement.kind == .function and span.first >= statement.span.first and span.last <= statement.span.last) {
        const function = statement.kind.function;
        for (module.parameters.items[function.params_first .. function.params_first + function.params_count]) |parameter| if (std.mem.eql(u8, parameter.name, name)) return true;
        for (module.statements.items[function.body_first .. function.body_first + function.body_count]) |body| {
            if (body.kind == .expression) {
                const expression = module.expressions.items[body.kind.expression];
                if (expression.kind == .assignment and std.mem.eql(u8, expression.kind.assignment.name, name)) return true;
            }
            if (body.kind == .function and std.mem.eql(u8, body.kind.function.name, name)) return true;
            if (body.kind == .control) if (body.kind.control.target) |target| if (std.mem.eql(u8, target, name)) return true;
        }
    };
    return false;
}
