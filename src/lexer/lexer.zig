const std = @import("std");
const config = @import("ravi_config");

pub const TokenKind = enum {
    identifier,
    keyword,
    number,
    string,
    newline,
    indent,
    dedent,
    comment,
    eof,
    colon,
    comma,
    dot,
    l_paren,
    r_paren,
    l_bracket,
    r_bracket,
    l_brace,
    r_brace,
    operator,
    arrow,
    fat_arrow,
};

pub const Token = struct {
    kind: TokenKind,
    lexeme: []const u8,
    line: usize,
    column: usize,
    end_line: usize = 0,
    end_column: usize = 0,
    start_offset: usize = 0,
    end_offset: usize = 0,
};

pub const LexError = std.mem.Allocator.Error || error{ InvalidIndentation, TabIndentation, UnterminatedString, InvalidCharacter, InvalidNumber, MixedLanguageKeyword, LineTooLong, StringTooLong };

pub const Lexer = struct {
    source: []const u8,
    allocator: std.mem.Allocator,
    tokens: std.ArrayListUnmanaged(Token) = .empty,
    indents: std.ArrayListUnmanaged(usize) = .empty,
    index: usize = 0,
    line: usize = 1,
    column: usize = 1,
    at_line_start: bool = true,
    language: config.SourceLanguage = .kn,
    error_line: usize = 1,
    error_column: usize = 1,
    error_offset: usize = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Lexer {
        var indents: std.ArrayListUnmanaged(usize) = .empty;
        try indents.append(allocator, 0);
        return .{ .source = source, .allocator = allocator, .indents = indents };
    }

    pub fn initWithLanguage(allocator: std.mem.Allocator, source: []const u8, language: config.SourceLanguage) !Lexer {
        var lexer = try init(allocator, source);
        lexer.language = language;
        return lexer;
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit(self.allocator);
        self.indents.deinit(self.allocator);
    }

    pub fn tokenize(self: *Lexer) LexError![]const Token {
        while (self.index < self.source.len) {
            self.error_line = self.line;
            self.error_column = self.column;
            self.error_offset = self.index;
            if (self.at_line_start) try self.consumeIndent();
            if (self.index >= self.source.len) break;
            const c = self.source[self.index];
            if (c == '\n') {
                try self.emit(.newline, self.index, 1);
                self.index += 1;
                self.line += 1;
                self.column = 1;
                self.at_line_start = true;
                continue;
            }
            if (c == ' ' or c == '\r') {
                self.index += 1;
                self.column += 1;
                continue;
            }
            if (c == '#') {
                const comment_start = self.index;
                const comment_column = self.column;
                while (self.index < self.source.len and self.source[self.index] != '\n') {
                    self.index += 1;
                    self.column += 1;
                }
                try self.emitAt(.comment, comment_start, self.index - comment_start, self.line, comment_column, self.line, self.column);
                continue;
            }
            if (std.ascii.isAlphabetic(c) or c == '_') {
                try self.scanIdentifier();
                continue;
            }
            if (std.ascii.isDigit(c)) {
                try self.scanNumber();
                continue;
            }
            if ((c == 'r' or c == 'R' or c == 'f' or c == 'F') and self.index + 1 < self.source.len and (self.source[self.index + 1] == '\'' or self.source[self.index + 1] == '"')) {
                self.index += 1;
                self.column += 1;
                try self.scanString(self.source[self.index]);
                const token = &self.tokens.items[self.tokens.items.len - 1];
                token.start_offset -= 1;
                token.column -= 1;
                token.lexeme = self.source[token.start_offset..token.end_offset];
                continue;
            }
            if (c == '\'' or c == '"') {
                try self.scanString(c);
                continue;
            }
            try self.scanPunctuation();
            self.at_line_start = false;
        }
        if (self.tokens.items.len > 0 and self.tokens.items[self.tokens.items.len - 1].kind != .newline) try self.emit(.newline, self.index, 0);
        while (self.indents.items.len > 1) {
            _ = self.indents.pop();
            try self.emit(.dedent, self.index, 0);
        }
        try self.emit(.eof, self.index, 0);
        return self.tokens.items;
    }

    fn consumeIndent(self: *Lexer) LexError!void {
        var width: usize = 0;
        const start = self.index;
        while (self.index < self.source.len and (self.source[self.index] == ' ' or self.source[self.index] == '\t')) : (self.index += 1) {
            if (self.source[self.index] == '\t') {
                self.error_offset = self.index;
                self.error_column = width + 1;
                return error.TabIndentation;
            }
            width += 1;
        }
        if (self.index < self.source.len and self.source[self.index] == '\n') return;
        if (width % config.spaces_per_indent != 0) return error.InvalidIndentation;
        const current = self.indents.items[self.indents.items.len - 1];
        if (width > current) {
            try self.indents.append(self.allocator, width);
            try self.emit(.indent, start, width);
        } else if (width < current) {
            while (self.indents.items.len > 1 and width < self.indents.items[self.indents.items.len - 1]) {
                _ = self.indents.pop();
                try self.emit(.dedent, start, 0);
            }
            if (width != self.indents.items[self.indents.items.len - 1]) return error.InvalidIndentation;
        }
        self.column = width + 1;
        self.at_line_start = false;
    }

    fn scanIdentifier(self: *Lexer) LexError!void {
        const start = self.index;
        while (self.index < self.source.len and (std.ascii.isAlphanumeric(self.source[self.index]) or self.source[self.index] == '_')) : (self.index += 1) {}
        const text = self.source[start..self.index];
        // Member names are always identifiers. This permits object.tago(),
        // object.if(), and similar names without weakening statement keywords.
        const member_name = self.tokens.items.len > 0 and self.tokens.items[self.tokens.items.len - 1].kind == .dot;
        const active = if (member_name) null else config.keywordCanonicalFor(self.language, text);
        if (!member_name and active == null and config.belongsToOtherLanguage(self.language, text)) return error.MixedLanguageKeyword;
        try self.emit(if (active != null) .keyword else .identifier, start, self.index - start);
        self.column += self.index - start;
    }
    fn scanNumber(self: *Lexer) LexError!void {
        const start = self.index;
        var dots: usize = 0;
        while (self.index < self.source.len and (std.ascii.isDigit(self.source[self.index]) or self.source[self.index] == '.')) : (self.index += 1) {
            if (self.source[self.index] == '.') {
                dots += 1;
                if (dots > 1) return error.InvalidNumber;
            }
        }
        try self.emit(.number, start, self.index - start);
        self.column += self.index - start;
    }
    fn scanString(self: *Lexer, quote: u8) LexError!void {
        const start = self.index;
        const start_line = self.line;
        const start_column = self.column;
        const triple = self.index + 2 < self.source.len and self.source[self.index + 1] == quote and self.source[self.index + 2] == quote;
        const delimiter: usize = if (triple) 3 else 1;
        self.index += delimiter;
        self.column += delimiter;
        while (self.index < self.source.len) {
            if (self.index - start > config.max_string_bytes) return error.StringTooLong;
            if (triple) {
                if (self.index + 2 < self.source.len and self.source[self.index] == quote and self.source[self.index + 1] == quote and self.source[self.index + 2] == quote) {
                    self.index += 3;
                    self.column += 3;
                    try self.emitAt(.string, start, self.index - start, start_line, start_column, self.line, self.column);
                    return;
                }
            } else if (self.source[self.index] == quote) {
                self.index += 1;
                self.column += 1;
                try self.emitAt(.string, start, self.index - start, start_line, start_column, self.line, self.column);
                return;
            }
            if (self.source[self.index] == '\\' and self.index + 1 < self.source.len) {
                self.index += 2;
                self.column += 2;
            } else {
                if (self.source[self.index] == '\n') {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
                self.index += 1;
            }
        }
        return error.UnterminatedString;
    }
    fn scanPunctuation(self: *Lexer) LexError!void {
        const start = self.index;
        const c = self.source[self.index];
        self.index += 1;
        const kind: TokenKind = switch (c) {
            ':', ',', '.', '(', ')', '[', ']', '{', '}' => switch (c) {
                ':' => .colon,
                ',' => .comma,
                '.' => .dot,
                '(' => .l_paren,
                ')' => .r_paren,
                '[' => .l_bracket,
                ']' => .r_bracket,
                '{' => .l_brace,
                '}' => .r_brace,
                else => unreachable,
            },
            '@' => .operator,
            '=' => if (self.index < self.source.len and self.source[self.index] == '>') blk: {
                self.index += 1;
                break :blk .fat_arrow;
            } else if (self.index < self.source.len and self.source[self.index] == '=') blk: {
                self.index += 1;
                break :blk .operator;
            } else .operator,
            '-' => if (self.index < self.source.len and self.source[self.index] == '>') blk: {
                self.index += 1;
                break :blk .arrow;
            } else .operator,
            '<', '>', '!' => if (self.index < self.source.len and self.source[self.index] == '=') blk: {
                self.index += 1;
                break :blk .operator;
            } else .operator,
            '+', '*', '/', '%' => .operator,
            else => return error.InvalidCharacter,
        };
        try self.emit(kind, start, self.index - start);
        self.column += self.index - start;
    }
    fn emit(self: *Lexer, kind: TokenKind, start: usize, length: usize) !void {
        try self.emitAt(kind, start, length, self.line, self.column, self.line, self.column + length);
    }

    fn emitAt(self: *Lexer, kind: TokenKind, start: usize, length: usize, line: usize, column: usize, end_line: usize, end_column: usize) !void {
        try self.tokens.append(self.allocator, .{ .kind = kind, .lexeme = self.source[start..@min(start + length, self.source.len)], .line = line, .column = column, .end_line = end_line, .end_column = end_column, .start_offset = start, .end_offset = @min(start + length, self.source.len) });
    }
};
