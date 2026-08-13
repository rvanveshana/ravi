const std = @import("std");
const lexer_mod = @import("ravi_lexer");
const ast = @import("ravi_ast");
const config = @import("ravi_config");
const helpers = @import("helpers.zig");
const parser_statements = @import("parser_statements.zig");
const parser_expressions = @import("parser_expressions.zig");

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
        try parser_statements.parseStatement(self, module, out, parseExpression);
    }

    fn parseExpression(self: *Parser, module: *ast.Module, min_bp: u8) ParseError!ast.ExprId {
        return parser_expressions.parseExpression(self, module, min_bp, parseFormattedExpression);
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

    fn skipTrivia(self: *Parser) void {
        while (self.at(.newline) or self.at(.indent) or self.at(.dedent) or self.at(.comment)) self.index += 1;
    }
    pub fn at(self: *Parser, kind: lexer_mod.TokenKind) bool {
        return self.index < self.tokens.len and self.tokens[self.index].kind == kind;
    }
    pub fn word(self: *Parser, text: []const u8) bool {
        if (self.index >= self.tokens.len) return false;
        const token = self.tokens[self.index];
        const actual = config.keywordCanonicalFor(self.language, token.lexeme) orelse token.lexeme;
        return std.mem.eql(u8, actual, text);
    }
};
