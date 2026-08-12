const std = @import("std");
const lexer_mod = @import("ravi_lexer");
const ast = @import("ravi_ast");
const config = @import("ravi_config");
const precedence = @import("precedence.zig");
const helpers = @import("helpers.zig");

pub const ParseError = std.mem.Allocator.Error || error{ UnexpectedToken, MissingSuite, InvalidImportOrder, MissingName, InvalidExpression, InvalidNumber, UnterminatedCall };

pub const Parser = struct {
    tokens: []const lexer_mod.Token,
    index: usize = 0,
    allocator: std.mem.Allocator,
    language: config.SourceLanguage = .kn,

    pub fn init(allocator: std.mem.Allocator, tokens: []const lexer_mod.Token) Parser {
        return .{ .allocator = allocator, .tokens = tokens };
    }
    pub fn initWithLanguage(allocator: std.mem.Allocator, tokens: []const lexer_mod.Token, language: config.SourceLanguage) Parser {
        return .{ .allocator = allocator, .tokens = tokens, .language = language };
    }

    pub fn parse(self: *Parser) ParseError!ast.Module {
        var module = ast.Module{ .allocator = self.allocator };
        errdefer module.deinit();
        while (!self.at(.eof)) {
            while (self.at(.newline) or self.at(.comment)) self.index += 1;
            if (self.at(.eof)) break;
            if (module.statements.items.len == 0 and self.at(.string)) module.docstring = self.tokens[self.index].lexeme;
            if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "@")) {
                const start = self.index;
                self.index += 1;
                if (!self.at(.identifier)) return error.MissingName;
                try module.decorators.append(self.allocator, .{ .name = self.tokens[self.index].lexeme, .span = .{ .first = start, .last = self.index + 1, .line = self.tokens[start].line } });
                self.index += 1;
                if (self.at(.newline)) self.index += 1;
                continue;
            }
            try self.parseStatement(&module, &module.statements);
        }
        return module;
    }

    pub fn parseRecovering(self: *Parser) !ast.Module {
        var module = ast.Module{ .allocator = self.allocator };
        errdefer module.deinit();
        while (!self.at(.eof)) {
            self.skipTrivia();
            if (self.at(.eof)) break;
            if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "@")) {
                const start = self.index;
                self.index += 1;
                if (!self.at(.identifier)) return error.MissingName;
                try module.decorators.append(self.allocator, .{ .name = self.tokens[self.index].lexeme, .span = .{ .first = start, .last = self.index + 1, .line = self.tokens[start].line } });
                self.index += 1;
                if (self.at(.newline)) self.index += 1;
                continue;
            }
            const before = self.index;
            self.parseStatement(&module, &module.statements) catch |err| {
                try module.diagnostics.append(self.allocator, .{ .message = @errorName(err), .span = .{ .first = before, .last = @min(before + 1, self.tokens.len), .line = self.tokens[before].line } });
                while (!self.at(.newline) and !self.at(.eof)) self.index += 1;
                if (self.at(.newline)) self.index += 1;
            };
            if (self.index == before) self.index += 1;
        }
        return module;
    }

    fn parseStatement(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt)) ParseError!void {
        const start = self.index;
        var visibility: ast.Visibility = .public;
        if (self.word("public") or self.word("private") or self.word("protected") or self.word("internal")) {
            visibility = if (self.word("private")) .private else if (self.word("protected")) .protected else if (self.word("internal")) .internal else .public;
            self.index += 1;
        }
        if (self.isImportStart()) try self.parseImport(module, out, start) else if (self.word("class")) try self.parseClass(module, out, start, visibility) else if (self.word("function")) try self.parseFunction(module, out, start, visibility) else if (self.word("return") or self.word("yield")) try self.parseReturn(module, out, start) else if (self.word("break") or self.word("continue") or self.word("pass") or self.word("raise")) try self.parseTransfer(module, out, start) else if (self.isControl()) try self.parseControl(module, out, start) else if (self.at(.identifier) and self.index + 1 < self.tokens.len and self.tokens[self.index + 1].kind == .colon) try self.parseTypedAssignment(module, out, start) else {
            const value = try self.parseExpression(module, 0);
            if (self.word("with")) {
                self.index += 1;
                var binding: ?[]const u8 = null;
                if (self.at(.identifier)) {
                    binding = self.tokens[self.index].lexeme;
                    self.index += 1;
                    if (!self.word("as")) return error.UnexpectedToken;
                    self.index += 1;
                }
                const body = try self.parseSuite(module);
                try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .context = .{ .value = value, .binding = binding, .body_first = body.first, .body_count = body.count } } });
                return;
            }
            if (self.at(.newline)) self.index += 1;
            try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .expression = value } });
        }
    }

    fn parseClass(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize, visibility: ast.Visibility) ParseError!void {
        self.index += 1;
        if (!self.at(.identifier)) return error.MissingName;
        const name = self.tokens[self.index].lexeme;
        self.index += 1;
        var base: ?[]const u8 = null;
        if (self.word("guru")) {
            self.index += 1;
            if (!self.at(.identifier)) return error.MissingName;
            base = self.tokens[self.index].lexeme;
            self.index += 1;
        }
        const body = try self.parseSuite(module);
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .class_decl = .{ .name = name, .base = base, .body_first = body.first, .body_count = body.count, .visibility = visibility } } });
    }

    fn parseImport(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        const module_name = self.tokens[self.index].lexeme;
        self.index += 1;
        if (!self.word("from")) return error.InvalidImportOrder;
        self.index += 1;
        const first = module.import_names.items.len;
        while (!self.at(.newline) and !self.at(.eof) and !self.word("import")) {
            if (!self.at(.identifier) and !self.at(.comma)) return error.InvalidImportOrder;
            if (self.at(.identifier)) try module.import_names.append(self.allocator, self.tokens[self.index].lexeme);
            self.index += 1;
        }
        if (module.import_names.items.len == first or !self.word("import")) return error.InvalidImportOrder;
        self.index += 1;
        if (self.at(.newline)) self.index += 1;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .import = .{ .module = module_name, .names_first = first, .names_count = module.import_names.items.len - first } } });
    }

    fn parseFunction(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize, visibility: ast.Visibility) ParseError!void {
        self.index += 1;
        if (!self.at(.identifier)) return error.MissingName;
        const name = self.tokens[self.index].lexeme;
        self.index += 1;
        const params_first = module.parameters.items.len;
        if (self.at(.l_paren)) {
            self.index += 1;
            while (!self.at(.r_paren)) {
                var parameter_kind: ast.ParameterKind = .positional;
                if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "*")) {
                    parameter_kind = .variadic;
                    self.index += 1;
                    if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "*")) {
                        parameter_kind = .keyword_variadic;
                        self.index += 1;
                    }
                }
                if (!self.at(.identifier)) return error.MissingName;
                const pstart = self.index;
                const pname = self.tokens[self.index].lexeme;
                self.index += 1;
                var annotation: ?[]const u8 = null;
                if (self.at(.colon)) {
                    self.index += 1;
                    if (!self.at(.identifier)) return error.MissingName;
                    annotation = self.tokens[self.index].lexeme;
                    self.index += 1;
                }
                var default_value: ?i64 = null;
                if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "=")) {
                    self.index += 1;
                    if (!self.at(.number)) return error.InvalidNumber;
                    default_value = std.fmt.parseInt(i64, self.tokens[self.index].lexeme, 10) catch return error.InvalidNumber;
                    self.index += 1;
                }
                try module.parameters.append(self.allocator, .{ .name = pname, .annotation = annotation, .span = .{ .first = pstart, .last = self.index, .line = self.tokens[pstart].line }, .default_value = default_value, .kind = parameter_kind });
                if (self.at(.comma)) self.index += 1 else if (!self.at(.r_paren)) return error.UnexpectedToken;
            }
            self.index += 1;
        }
        const params_count = module.parameters.items.len - params_first;
        var return_type: ?[]const u8 = null;
        if (self.at(.arrow)) {
            self.index += 1;
            // Built-in `none` is lexed as a keyword, while user-defined and
            // other primitive return types are identifiers.
            if (!self.at(.identifier) and !(self.at(.keyword) and std.mem.eql(u8, self.tokens[self.index].lexeme, "none"))) return error.MissingName;
            return_type = self.tokens[self.index].lexeme;
            self.index += 1;
        }
        const statement_index = out.items.len;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = start, .line = self.tokens[start].line }, .kind = .{ .transfer = "pass" } });
        const body = try self.parseSuite(module);
        out.items[statement_index] = .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .function = .{ .name = name, .params_first = params_first, .params_count = params_count, .return_type = return_type, .body_first = body.first, .body_count = body.count, .decorators_first = 0, .decorators_count = module.decorators.items.len, .visibility = visibility } } };
    }

    fn parseReturn(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        self.index += 1;
        var value: ?ast.ExprId = null;
        if (!self.at(.newline) and !self.at(.dedent) and !self.at(.eof)) value = try self.parseExpression(module, 0);
        if (self.at(.newline)) self.index += 1;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .return_stmt = value } });
    }

    fn parseTransfer(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        const keyword = config.keywordCanonicalFor(self.language, self.tokens[self.index].lexeme) orelse self.tokens[self.index].lexeme;
        const is_raise = self.word("raise");
        self.index += 1;
        if (is_raise) {
            var value: ?ast.ExprId = null;
            if (!self.at(.newline) and !self.at(.dedent) and !self.at(.eof)) value = try self.parseExpression(module, 0);
            if (self.at(.newline)) self.index += 1;
            try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .raise_stmt = value } });
            return;
        }
        if (self.at(.newline)) self.index += 1;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .transfer = keyword } });
    }

    fn parseTypedAssignment(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        const name = self.tokens[self.index].lexeme;
        self.index += 1;
        self.index += 1;
        if (!self.at(.identifier)) return error.MissingName;
        const annotation = self.tokens[self.index].lexeme;
        self.index += 1;
        var array_type = false;
        if (self.at(.l_bracket)) {
            self.index += 1;
            if (!self.at(.r_bracket)) return error.UnexpectedToken;
            self.index += 1;
            array_type = true;
        }
        if (!self.at(.operator) or !std.mem.eql(u8, self.tokens[self.index].lexeme, "=")) return error.UnexpectedToken;
        self.index += 1;
        const value = try self.parseExpression(module, 0);
        if (self.at(.newline)) self.index += 1;
        const expression = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .assignment = .{ .name = name, .value = value, .annotation = annotation, .array_type = array_type } } });
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .expression = expression } });
    }

    fn parseControl(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        const keyword = config.keywordCanonicalFor(self.language, self.tokens[self.index].lexeme) orelse self.tokens[self.index].lexeme;
        self.index += 1;
        const statement_index = out.items.len;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = start, .line = self.tokens[start].line }, .kind = .{ .transfer = "" } });
        if (std.mem.eql(u8, keyword, "try")) {
            const body = try self.parseSuite(module);
            var except_first: usize = 0;
            var except_count: usize = 0;
            var except_binding: ?[]const u8 = null;
            var except_match: ?ast.ExprId = null;
            var finally_first: usize = 0;
            var finally_count: usize = 0;
            if (self.word("except")) {
                self.index += 1;
                if (self.at(.number)) {
                    except_match = try self.parseExpression(module, 0);
                } else if (self.at(.identifier)) {
                    except_binding = self.tokens[self.index].lexeme;
                    self.index += 1;
                }
                while (!self.at(.colon) and !self.at(.newline) and !self.at(.eof)) self.index += 1;
                const except_body = try self.parseSuite(module);
                except_first = except_body.first;
                except_count = except_body.count;
            }
            if (self.word("finally")) {
                self.index += 1;
                const finally_body = try self.parseSuite(module);
                finally_first = finally_body.first;
                finally_count = finally_body.count;
            }
            out.items[statement_index] = .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .try_stmt = .{ .body_first = body.first, .body_count = body.count, .except_first = except_first, .except_count = except_count, .except_binding = except_binding, .except_match = except_match, .finally_first = finally_first, .finally_count = finally_count } } };
            return;
        }
        if (std.mem.eql(u8, keyword, "for")) {
            if (!self.at(.identifier)) return error.MissingName;
            const target = self.tokens[self.index].lexeme;
            self.index += 1;
            if (!self.word("in")) return error.UnexpectedToken;
            self.index += 1;
            const iterable = try self.parseExpression(module, 0);
            const body = try self.parseSuite(module);
            out.items[statement_index] = .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .control = .{ .keyword = keyword, .condition = null, .body_first = body.first, .body_count = body.count, .target = target, .iterable = iterable } } };
            return;
        }
        var condition: ?ast.ExprId = null;
        if (!self.at(.colon)) condition = try self.parseExpression(module, 0);
        const body = try self.parseSuite(module);
        var else_first: usize = 0;
        var else_count: usize = 0;
        if (std.mem.eql(u8, keyword, "if") and self.word("elif")) {
            else_first = out.items.len;
            try self.parseControl(module, out, self.index);
            else_count = out.items.len - else_first;
        } else if ((std.mem.eql(u8, keyword, "if") or std.mem.eql(u8, keyword, "elif")) and self.word("else")) {
            self.index += 1;
            const else_body = try self.parseSuite(module);
            else_first = else_body.first;
            else_count = else_body.count;
        }
        out.items[statement_index] = .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .control = .{ .keyword = keyword, .condition = condition, .body_first = body.first, .body_count = body.count, .else_first = else_first, .else_count = else_count } } };
    }

    fn parseSuite(self: *Parser, module: *ast.Module) ParseError!struct { first: usize, count: usize } {
        if (!self.at(.colon)) return error.MissingSuite;
        self.index += 1;
        if (!self.at(.newline)) return error.MissingSuite;
        self.index += 1;
        if (!self.at(.indent)) return error.MissingSuite;
        self.index += 1;
        const first = module.statements.items.len;
        while (!self.at(.dedent) and !self.at(.eof)) {
            while (self.at(.newline) or self.at(.comment)) self.index += 1;
            if (self.at(.dedent) or self.at(.eof)) break;
            try self.parseStatement(module, &module.statements);
        }
        if (self.at(.dedent)) self.index += 1;
        return .{ .first = first, .count = module.statements.items.len - first };
    }

    fn parseExpression(self: *Parser, module: *ast.Module, min_bp: u8) ParseError!ast.ExprId {
        const start = self.index;
        var left = try self.parsePrefix(module);
        while (true) {
            if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "=")) {
                if (min_bp > 1) break;
                const target = module.expressions.items[left].kind;
                const is_member_target = switch (target) {
                    .member => true,
                    else => false,
                };
                const name = switch (target) {
                    .name => |value| value,
                    .member => |value| value.name,
                    else => return error.InvalidExpression,
                };
                self.index += 1;
                const value = try self.parseExpression(module, 1);
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .assignment = .{ .name = name, .value = value, .target = if (is_member_target) left else null } } });
                continue;
            }
            if (self.at(.dot)) {
                self.index += 1;
                if (!self.at(.identifier)) return error.MissingName;
                const member_name = self.tokens[self.index].lexeme;
                self.index += 1;
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .member = .{ .object = left, .name = member_name } } });
                continue;
            }
            if (self.at(.l_paren)) {
                if (90 < min_bp) break;
                self.index += 1;
                var arguments: std.ArrayListUnmanaged(ast.ExprId) = .empty;
                var keyword_names: std.ArrayListUnmanaged([]const u8) = .empty;
                defer arguments.deinit(self.allocator);
                defer keyword_names.deinit(self.allocator);
                while (!self.at(.r_paren)) {
                    const argument = try self.parseExpression(module, 0);
                    const argument_kind = module.expressions.items[argument].kind;
                    if (argument_kind == .assignment and argument_kind.assignment.target == null) {
                        try keyword_names.append(self.allocator, argument_kind.assignment.name);
                        try arguments.append(self.allocator, argument_kind.assignment.value);
                    } else try arguments.append(self.allocator, argument);
                    if (self.at(.comma)) self.index += 1 else if (!self.at(.r_paren)) return error.UnterminatedCall;
                }
                self.index += 1;
                const first_arg = module.call_args.items.len;
                try module.call_args.appendSlice(self.allocator, arguments.items);
                const keyword_first = module.call_keywords.items.len;
                try module.call_keywords.appendSlice(self.allocator, keyword_names.items);
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .call = .{ .callee = left, .first_arg = first_arg, .arg_count = arguments.items.len, .keyword_first = keyword_first, .keyword_count = keyword_names.items.len } } });
                continue;
            }
            if (self.at(.l_bracket)) {
                self.index += 1;
                if (self.at(.colon)) {
                    self.index += 1;
                    const finish = if (self.at(.r_bracket)) null else try self.parseExpression(module, 0);
                    if (!self.at(.r_bracket)) return error.UnexpectedToken;
                    self.index += 1;
                    left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .slice = .{ .object = left, .start = null, .end = finish } } });
                    continue;
                }
                const index = try self.parseExpression(module, 0);
                if (self.at(.colon)) {
                    self.index += 1;
                    const finish = if (self.at(.r_bracket)) null else try self.parseExpression(module, 0);
                    if (!self.at(.r_bracket)) return error.UnexpectedToken;
                    self.index += 1;
                    left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .slice = .{ .object = left, .start = index, .end = finish } } });
                } else {
                    if (!self.at(.r_bracket)) return error.UnexpectedToken;
                    self.index += 1;
                    left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .index = .{ .object = left, .index = index } } });
                }
                continue;
            }
            const info = precedence.binaryInfo(self) orelse break;
            if (info.left_bp < min_bp) break;
            self.index += 1;
            const right = try self.parseExpression(module, info.right_bp);
            left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .binary = .{ .op = info.op, .left = left, .right = right } } });
        }
        return left;
    }

    fn parsePrefix(self: *Parser, module: *ast.Module) ParseError!ast.ExprId {
        const token = self.tokens[self.index];
        const start = self.index;
        if (self.word("function")) return self.parseLambda(module, start);
        if (self.at(.operator) and (std.mem.eql(u8, token.lexeme, "-") or std.mem.eql(u8, token.lexeme, "+"))) {
            self.index += 1;
            const operand = try self.parseExpression(module, 80);
            if (std.mem.eql(u8, token.lexeme, "+")) return operand;
            return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .unary = .{ .op = .negate, .operand = operand } } });
        }
        if (self.word("not")) {
            self.index += 1;
            const operand = try self.parseExpression(module, 80);
            return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .unary = .{ .op = .not, .operand = operand } } });
        }
        if (token.kind == .string and token.lexeme.len > 1 and (token.lexeme[0] == 'f' or token.lexeme[0] == 'F')) return self.parseFormattedString(module, start);
        if (self.at(.l_paren)) {
            self.index += 1;
            const first = module.expressions.items.len;
            var count: usize = 0;
            const value = try self.parseExpression(module, 0);
            count += 1;
            if (self.at(.comma)) {
                while (self.at(.comma)) {
                    self.index += 1;
                    _ = try self.parseExpression(module, 0);
                    count += 1;
                }
                if (!self.at(.r_paren)) return error.UnexpectedToken;
                self.index += 1;
                return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .tuple = .{ .first = first, .count = count } } });
            }
            if (!self.at(.r_paren)) return error.UnexpectedToken;
            self.index += 1;
            return value;
        }
        if (self.at(.l_bracket)) {
            self.index += 1;
            const first = module.expressions.items.len;
            var count: usize = 0;
            while (!self.at(.r_bracket)) {
                _ = try self.parseExpression(module, 0);
                count += 1;
                if (self.at(.comma)) self.index += 1 else if (!self.at(.r_bracket)) return error.UnexpectedToken;
            }
            self.index += 1;
            return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .array = .{ .first = first, .count = count } } });
        }
        if (self.at(.l_brace)) {
            self.index += 1;
            const first = module.expressions.items.len;
            var count: usize = 0;
            while (!self.at(.r_brace)) {
                _ = try self.parseExpression(module, 0);
                if (self.at(.colon)) {
                    self.index += 1;
                    _ = try self.parseExpression(module, 0);
                    count += 1;
                } else count += 1;
                if (self.at(.comma)) self.index += 1 else if (!self.at(.r_brace)) return error.UnexpectedToken;
            }
            self.index += 1;
            return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = if (count == 0 or self.tokens[start + 2].kind == .colon) .{ .map = .{ .first = first, .count = count } } else .{ .set = .{ .first = first, .count = count } } });
        }
        self.index += 1;
        const kind: ast.Expr.Kind = switch (token.kind) {
            .number => if (std.mem.indexOfScalar(u8, token.lexeme, '.') != null) .{ .float = std.fmt.parseFloat(f64, token.lexeme) catch return error.InvalidNumber } else .{ .integer = std.fmt.parseInt(i64, token.lexeme, 10) catch return error.InvalidNumber },
            .string => .{ .string = token.lexeme },
            .identifier => .{ .name = token.lexeme },
            .keyword => if (std.mem.eql(u8, token.lexeme, "true")) .{ .boolean = true } else if (std.mem.eql(u8, token.lexeme, "false")) .{ .boolean = false } else if (std.mem.eql(u8, token.lexeme, "none")) .none else return error.InvalidExpression,
            else => return error.InvalidExpression,
        };
        return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = kind });
    }

    fn parseFormattedString(self: *Parser, module: *ast.Module, start: usize) ParseError!ast.ExprId {
        const token = self.tokens[self.index];
        const raw = token.lexeme;
        const triple = raw.len >= 8 and raw[1] == raw[2] and raw[2] == raw[3];
        const content_start: usize = if (triple) 4 else 2;
        const trim: usize = if (triple) 3 else 1;
        if (raw.len < content_start + trim or raw[raw.len - trim] != raw[content_start - 1]) return error.InvalidExpression;
        const content_end = raw.len - trim;
        const first_arg = module.format_args.items.len;
        var argument_count: usize = 0;
        var cursor = content_start;
        while (cursor < content_end) {
            if (raw[cursor] == '{') {
                if (cursor + 1 < content_end and raw[cursor + 1] == '{') {
                    cursor += 2;
                    continue;
                }
                const expression_start = cursor + 1;
                const close = helpers.formattedPlaceholderEnd(raw, expression_start, content_end) orelse return error.InvalidExpression;
                if (close == expression_start) return error.InvalidExpression;
                const expression = raw[expression_start..close];
                const expression_end = helpers.formatExpressionEnd(expression);
                if (expression_end == 0) return error.InvalidExpression;
                const expression_id = try self.parseFormattedExpression(module, expression[0..expression_end], start, token.line);
                try module.format_args.append(self.allocator, expression_id);
                argument_count += 1;
                cursor = close + 1;
            } else if (raw[cursor] == '}') {
                if (cursor + 1 < content_end and raw[cursor + 1] == '}') {
                    cursor += 2;
                    continue;
                }
                return error.InvalidExpression;
            } else cursor += 1;
        }
        self.index += 1;
        return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .formatted_string = .{ .template = raw, .first_arg = first_arg, .arg_count = argument_count } } });
    }

    fn parseFormattedExpression(self: *Parser, module: *ast.Module, source: []const u8, start: usize, line: usize) ParseError!ast.ExprId {
        var scan = lexer_mod.Lexer.initWithLanguage(self.allocator, source, self.language) catch return error.OutOfMemory;
        defer scan.deinit();
        const tokens = scan.tokenize() catch return error.InvalidExpression;
        var nested_parser = Parser.initWithLanguage(self.allocator, tokens, self.language);
        var nested = nested_parser.parse() catch return error.InvalidExpression;
        defer nested.deinit();
        if (nested.diagnostics.items.len != 0 or nested.statements.items.len != 1) return error.InvalidExpression;
        const nested_id = switch (nested.statements.items[0].kind) {
            .expression => |expression| expression,
            else => return error.InvalidExpression,
        };
        const offset = module.expressions.items.len;
        for (nested.expressions.items) |expression| {
            var copy = expression;
            helpers.remapExpressionIds(&copy, offset) catch return error.InvalidExpression;
            copy.span = .{ .first = start, .last = start + source.len, .line = line };
            try module.expressions.append(self.allocator, copy);
        }
        return @intCast(offset + @as(usize, nested_id));
    }

    fn parseLambda(self: *Parser, module: *ast.Module, start: usize) ParseError!ast.ExprId {
        self.index += 1;
        const first = module.parameters.items.len;
        if (!self.at(.l_paren)) return error.UnexpectedToken;
        self.index += 1;
        while (!self.at(.r_paren)) {
            if (!self.at(.identifier)) return error.MissingName;
            const p = self.tokens[self.index];
            self.index += 1;
            var annotation: ?[]const u8 = null;
            if (self.at(.colon)) {
                self.index += 1;
                if (!self.at(.identifier)) return error.MissingName;
                annotation = self.tokens[self.index].lexeme;
                self.index += 1;
            }
            try module.parameters.append(self.allocator, .{ .name = p.lexeme, .annotation = annotation, .span = .{ .first = self.index - 1, .last = self.index, .line = p.line } });
            if (self.at(.comma)) self.index += 1 else if (!self.at(.r_paren)) return error.UnexpectedToken;
        }
        self.index += 1;
        if (self.at(.arrow)) {
            self.index += 1;
            if (!self.at(.identifier)) return error.MissingName;
            self.index += 1;
        }
        if (!self.at(.fat_arrow)) return error.MissingSuite;
        self.index += 1;
        const body = try self.parseExpression(module, 0);
        return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .lambda = .{ .params_first = first, .params_count = module.parameters.items.len - first, .body = body } } });
    }

    fn skipTrivia(self: *Parser) void {
        while (self.at(.newline) or self.at(.indent) or self.at(.dedent) or self.at(.comment)) self.index += 1;
    }
    fn at(self: *Parser, kind: lexer_mod.TokenKind) bool {
        return self.index < self.tokens.len and self.tokens[self.index].kind == kind;
    }
    fn word(self: *Parser, text: []const u8) bool {
        if (self.index >= self.tokens.len) return false;
        const token = self.tokens[self.index];
        const actual = config.keywordCanonicalFor(self.language, token.lexeme) orelse token.lexeme;
        return std.mem.eql(u8, actual, text);
    }
    fn isControl(self: *Parser) bool {
        return self.word("if") or self.word("elif") or self.word("else") or self.word("while") or self.word("for") or self.word("try") or self.word("except") or self.word("finally");
    }
    fn isImportStart(self: *Parser) bool {
        return self.at(.identifier) and self.index + 1 < self.tokens.len and config.keywordCanonicalFor(self.language, self.tokens[self.index + 1].lexeme) != null and std.mem.eql(u8, config.keywordCanonicalFor(self.language, self.tokens[self.index + 1].lexeme).?, "from");
    }
};

fn appendExpr(module: *ast.Module, expression: ast.Expr) ParseError!ast.ExprId {
    const id: ast.ExprId = @intCast(module.expressions.items.len);
    try module.expressions.append(module.allocator, expression);
    return id;
}
