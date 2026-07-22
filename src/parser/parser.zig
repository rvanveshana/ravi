const std = @import("std");
const lexer_mod = @import("ravi_lexer");
const ast = @import("ravi_ast");
const config = @import("ravi_config");
const precedence = @import("precedence.zig");

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
            self.skipTrivia();
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
        if (self.isImportStart()) try self.parseImport(module, out, start) else if (self.word("kriya")) try self.parseFunction(module, out, start) else if (self.word("kodu") or self.word("taru")) try self.parseReturn(module, out, start) else if (self.word("nillu") or self.word("munde") or self.word("yese")) try self.parseTransfer(module, out, start) else if (self.isControl()) try self.parseControl(module, out, start) else if (self.at(.identifier) and self.index + 1 < self.tokens.len and self.tokens[self.index + 1].kind == .colon) try self.parseTypedAssignment(module, out, start) else {
            const value = try self.parseExpression(module, 0);
            if (self.at(.newline)) self.index += 1;
            try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .expression = value } });
        }
    }

    fn parseImport(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        const module_name = self.tokens[self.index].lexeme;
        self.index += 1;
        if (!self.word("inda")) return error.InvalidImportOrder;
        self.index += 1;
        const first = module.import_names.items.len;
        while (!self.at(.newline) and !self.at(.eof) and !self.word("tago")) {
            if (!self.at(.identifier) and !self.at(.comma)) return error.InvalidImportOrder;
            if (self.at(.identifier)) try module.import_names.append(self.allocator, self.tokens[self.index].lexeme);
            self.index += 1;
        }
        if (module.import_names.items.len == first or !self.word("tago")) return error.InvalidImportOrder;
        self.index += 1;
        if (self.at(.newline)) self.index += 1;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .import = .{ .module = module_name, .names_first = first, .names_count = module.import_names.items.len - first } } });
    }

    fn parseFunction(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        self.index += 1;
        if (!self.at(.identifier)) return error.MissingName;
        const name = self.tokens[self.index].lexeme;
        self.index += 1;
        const params_first = module.parameters.items.len;
        if (self.at(.l_paren)) {
            self.index += 1;
            while (!self.at(.r_paren)) {
                if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "*")) {
                    self.index += 1;
                    if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "*")) self.index += 1;
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
                if (self.at(.operator) and std.mem.eql(u8, self.tokens[self.index].lexeme, "=")) {
                    self.index += 1;
                    if (!self.at(.number)) return error.InvalidNumber;
                    self.index += 1;
                }
                try module.parameters.append(self.allocator, .{ .name = pname, .annotation = annotation, .span = .{ .first = pstart, .last = self.index, .line = self.tokens[pstart].line } });
                if (self.at(.comma)) self.index += 1 else if (!self.at(.r_paren)) return error.UnexpectedToken;
            }
            self.index += 1;
        }
        var return_type: ?[]const u8 = null;
        if (self.at(.arrow)) {
            self.index += 1;
            if (!self.at(.identifier)) return error.MissingName;
            return_type = self.tokens[self.index].lexeme;
            self.index += 1;
        }
        const body = try self.parseSuite(module);
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .function = .{ .name = name, .params_first = params_first, .params_count = module.parameters.items.len - params_first, .return_type = return_type, .body_first = body.first, .body_count = body.count, .decorators_first = 0, .decorators_count = module.decorators.items.len, .visibility = .internal } } });
    }

    fn parseReturn(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        self.index += 1;
        var value: ?ast.ExprId = null;
        if (!self.at(.newline) and !self.at(.dedent) and !self.at(.eof)) value = try self.parseExpression(module, 0);
        if (self.at(.newline)) self.index += 1;
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .return_stmt = value } });
    }

    fn parseTransfer(self: *Parser, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
        _ = module;
        const keyword = self.tokens[self.index].lexeme;
        const is_raise = self.word("yese");
        self.index += 1;
        if (is_raise) {
            while (!self.at(.newline) and !self.at(.eof)) self.index += 1;
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
        const keyword = self.tokens[self.index].lexeme;
        self.index += 1;
        var condition: ?ast.ExprId = null;
        if (!self.at(.colon)) condition = try self.parseExpression(module, 0);
        const body = try self.parseSuite(module);
        try out.append(self.allocator, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .control = .{ .keyword = keyword, .condition = condition, .body_first = body.first, .body_count = body.count } } });
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
            self.skipTrivia();
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
                const name = switch (target) {
                    .name => |value| value,
                    else => return error.InvalidExpression,
                };
                self.index += 1;
                const value = try self.parseExpression(module, 1);
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .assignment = .{ .name = name, .value = value } } });
                continue;
            }
            if (self.at(.dot)) {
                self.index += 1;
                if (!self.at(.identifier)) return error.MissingName;
                self.index += 1;
                if (self.at(.l_paren)) {
                    self.index += 1;
                    while (!self.at(.r_paren)) {
                        _ = try self.parseExpression(module, 0);
                        if (self.at(.comma)) self.index += 1 else if (!self.at(.r_paren)) return error.UnexpectedToken;
                    }
                    self.index += 1;
                }
                continue;
            }
            if (self.at(.l_paren)) {
                if (90 < min_bp) break;
                self.index += 1;
                const first_arg = module.expressions.items.len;
                var count: usize = 0;
                while (!self.at(.r_paren)) {
                    _ = try self.parseExpression(module, 0);
                    count += 1;
                    if (self.at(.comma)) self.index += 1 else if (!self.at(.r_paren)) return error.UnterminatedCall;
                }
                self.index += 1;
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = self.tokens[start].line }, .kind = .{ .call = .{ .callee = left, .first_arg = first_arg, .arg_count = count } } });
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
        if (self.word("kriya")) return self.parseLambda(module, start);
        if (self.at(.operator) and (std.mem.eql(u8, token.lexeme, "-") or std.mem.eql(u8, token.lexeme, "+"))) {
            self.index += 1;
            const operand = try self.parseExpression(module, 80);
            if (std.mem.eql(u8, token.lexeme, "+")) return operand;
            return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .unary = .{ .op = .negate, .operand = operand } } });
        }
        if (self.word("alla")) {
            self.index += 1;
            const operand = try self.parseExpression(module, 80);
            return appendExpr(module, .{ .span = .{ .first = start, .last = self.index, .line = token.line }, .kind = .{ .unary = .{ .op = .not, .operand = operand } } });
        }
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
        const expected = config.keywordCanonicalFor(.kn, text) orelse text;
        const actual = config.keywordCanonicalFor(self.language, token.lexeme) orelse token.lexeme;
        return std.mem.eql(u8, actual, expected);
    }
    fn isControl(self: *Parser) bool {
        return self.word("adre") or self.word("inadre") or self.word("illa") or self.word("vargu") or self.word("prati") or self.word("nodu") or self.word("tappu") or self.word("kone");
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
