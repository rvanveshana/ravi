const std = @import("std");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
const config = @import("ravi_config");
const formatter = @import("ravi_formatter");

pub const Position = struct { line: u32, character: u32 };
pub const Range = struct { start: Position, end: Position };
pub const Diagnostic = struct { range: Range, code: []const u8, message: []const u8, fix: ?TextEdit = null };
pub const Completion = struct { label: []const u8, detail: []const u8 };
pub const Symbol = struct { name: []const u8, kind: []const u8, line: u32 };
pub const Reference = struct { line: u32, character: u32 };
pub const TextEdit = struct { range: Range, replacement: []const u8 };
pub const SemanticToken = struct { line: u32, character: u32, length: u32, token_type: u32 };

const Document = struct {
    uri: []const u8,
    text: []const u8,
    version: i64,
    language: config.SourceLanguage,
};

/// Protocol-independent LSP state. A JSON-RPC transport can call these methods
/// from stdio, sockets, or in-process editor tests without duplicating compiler
/// behavior.
pub const Server = struct {
    allocator: std.mem.Allocator,
    documents: std.ArrayListUnmanaged(Document) = .empty,

    pub fn init(allocator: std.mem.Allocator) Server {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Server) void {
        for (self.documents.items) |document| {
            self.allocator.free(document.uri);
            self.allocator.free(document.text);
        }
        self.documents.deinit(self.allocator);
    }

    pub fn open(self: *Server, uri: []const u8, text: []const u8, version: i64) !void {
        if (self.find(uri)) |index| return self.replace(index, text, version);
        const owned_uri = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(owned_uri);
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);
        const language = (config.languageFromHeader(text) catch .kn) orelse .kn;
        try self.documents.append(self.allocator, .{ .uri = owned_uri, .text = owned_text, .version = version, .language = language });
    }

    pub fn change(self: *Server, uri: []const u8, text: []const u8, version: i64) !void {
        const index = self.find(uri) orelse return error.UnknownDocument;
        if (version <= self.documents.items[index].version) return error.StaleDocumentVersion;
        try self.replace(index, text, version);
    }

    pub fn close(self: *Server, uri: []const u8) void {
        const index = self.find(uri) orelse return;
        const document = self.documents.orderedRemove(index);
        self.allocator.free(document.uri);
        self.allocator.free(document.text);
    }

    pub fn diagnostics(self: *Server, uri: []const u8, allocator: std.mem.Allocator) ![]Diagnostic {
        const index = self.find(uri) orelse return error.UnknownDocument;
        const document = self.documents.items[index];
        var scan = try lexer.Lexer.initWithLanguage(allocator, document.text, document.language);
        defer scan.deinit();
        const tokens = scan.tokenize() catch |err| {
            const result = try allocator.alloc(Diagnostic, 1);
            result[0] = .{
                .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 1 } },
                .code = "RAVI-LEX-001",
                .message = @errorName(err),
            };
            return result;
        };
        var syntax_parser = parser.Parser.initWithLanguage(allocator, tokens, document.language);
        var syntax = syntax_parser.parseRecovering() catch |err| {
            const result = try allocator.alloc(Diagnostic, 1);
            result[0] = .{
                .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 0, .character = 1 } },
                .code = "RAVI-PARSE-001",
                .message = @errorName(err),
            };
            return result;
        };
        defer syntax.deinit();
        const result = try allocator.alloc(Diagnostic, syntax.diagnostics.items.len);
        for (syntax.diagnostics.items, 0..) |issue, diagnostic_index| {
            const line = if (issue.span.line > 0) issue.span.line - 1 else 0;
            result[diagnostic_index] = .{
                .range = .{ .start = .{ .line = @intCast(line), .character = 0 }, .end = .{ .line = @intCast(line), .character = 1 } },
                .code = "RAVI-PARSE-001",
                .message = issue.message,
                .fix = if (std.mem.eql(u8, issue.message, "MissingName")) .{ .range = .{ .start = .{ .line = @intCast(line), .character = 0 }, .end = .{ .line = @intCast(line), .character = 0 } }, .replacement = "name" } else null,
            };
        }
        return result;
    }

    pub fn codeActions(self: *Server, uri: []const u8, allocator: std.mem.Allocator) ![]Diagnostic {
        const found = try self.diagnostics(uri, allocator);
        var count: usize = 0;
        for (found) |diagnostic| {
            if (diagnostic.fix != null) count += 1;
        }
        const actions = try allocator.alloc(Diagnostic, count);
        var index: usize = 0;
        for (found) |diagnostic| {
            if (diagnostic.fix != null) {
                actions[index] = diagnostic;
                index += 1;
            }
        }
        allocator.free(found);
        return actions;
    }

    pub fn completions(self: *const Server, language: config.SourceLanguage, allocator: std.mem.Allocator) ![]Completion {
        _ = self;
        const labels = if (language == .kn)
            [_][]const u8{ "kriya", "kodu", "adre", "illa", "prati", "vargu", "roopa", "nodu", "tappu" }
        else
            [_][]const u8{ "function", "return", "if", "else", "for", "while", "class", "try", "except" };
        const result = try allocator.alloc(Completion, labels.len);
        for (labels, 0..) |label, index| result[index] = .{ .label = label, .detail = "Ravi keyword" };
        return result;
    }

    pub fn documentLanguage(self: *const Server, uri: []const u8) ?config.SourceLanguage {
        const index = self.find(uri) orelse return null;
        return self.documents.items[index].language;
    }

    pub fn semanticTokens(self: *const Server, uri: []const u8, allocator: std.mem.Allocator) ![]SemanticToken {
        const index = self.find(uri) orelse return error.UnknownDocument;
        const document = self.documents.items[index];
        var scan = try lexer.Lexer.initWithLanguage(allocator, document.text, document.language);
        defer scan.deinit();
        const tokens = try scan.tokenize();
        var result = std.ArrayListUnmanaged(SemanticToken).empty;
        errdefer result.deinit(allocator);
        for (tokens) |token| {
            const token_type: ?u32 = switch (token.kind) {
                .keyword => 0,
                .identifier => 1,
                .number => 2,
                .string => 3,
                .comment => 4,
                .operator, .arrow, .fat_arrow => 5,
                else => null,
            };
            if (token_type) |kind| try result.append(allocator, .{ .line = @intCast(if (token.line > 0) token.line - 1 else 0), .character = @intCast(token.column -| 1), .length = @intCast(token.lexeme.len), .token_type = kind });
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn documentSymbols(self: *const Server, uri: []const u8, allocator: std.mem.Allocator) ![]Symbol {
        const index = self.find(uri) orelse return error.UnknownDocument;
        const document = self.documents.items[index];
        var scan = try lexer.Lexer.initWithLanguage(allocator, document.text, document.language);
        defer scan.deinit();
        const tokens = try scan.tokenize();
        var result = std.ArrayListUnmanaged(Symbol).empty;
        errdefer result.deinit(allocator);
        for (tokens, 0..) |token, token_index| {
            if (token.kind != .keyword or token_index + 1 >= tokens.len) continue;
            const kind: []const u8 = if (config.keywordIsCanonical(document.language, token.lexeme, "function")) "Function" else if (config.keywordIsCanonical(document.language, token.lexeme, "class")) "Class" else continue;
            const name = tokens[token_index + 1];
            if (name.kind != .identifier) continue;
            try result.append(allocator, .{ .name = name.lexeme, .kind = kind, .line = @intCast(if (name.line > 0) name.line - 1 else 0) });
        }
        return result.toOwnedSlice(allocator);
    }

    pub fn references(self: *const Server, uri: []const u8, name: []const u8, allocator: std.mem.Allocator) ![]Reference {
        const index = self.find(uri) orelse return error.UnknownDocument;
        const document = self.documents.items[index];
        var scan = try lexer.Lexer.initWithLanguage(allocator, document.text, document.language);
        defer scan.deinit();
        const tokens = try scan.tokenize();
        var result = std.ArrayListUnmanaged(Reference).empty;
        errdefer result.deinit(allocator);
        for (tokens) |token| if (token.kind == .identifier and std.mem.eql(u8, token.lexeme, name)) {
            try result.append(allocator, .{ .line = @intCast(if (token.line > 0) token.line - 1 else 0), .character = @intCast(token.column) });
        };
        return result.toOwnedSlice(allocator);
    }

    pub fn definition(self: *const Server, uri: []const u8, name: []const u8, allocator: std.mem.Allocator) !?Reference {
        const index = self.find(uri) orelse return error.UnknownDocument;
        const document = self.documents.items[index];
        var scan = try lexer.Lexer.initWithLanguage(allocator, document.text, document.language);
        defer scan.deinit();
        const tokens = try scan.tokenize();
        for (tokens, 0..) |token, token_index| {
            if (token.kind != .keyword or token_index + 1 >= tokens.len) continue;
            const declaration = config.keywordIsCanonical(document.language, token.lexeme, "function") or
                config.keywordIsCanonical(document.language, token.lexeme, "class");
            if (declaration and tokens[token_index + 1].kind == .identifier and
                std.mem.eql(u8, tokens[token_index + 1].lexeme, name))
            {
                const found = tokens[token_index + 1];
                return .{ .line = @intCast(if (found.line > 0) found.line - 1 else 0), .character = @intCast(found.column) };
            }
        }
        return null;
    }

    pub fn rename(self: *const Server, uri: []const u8, name: []const u8, replacement: []const u8, allocator: std.mem.Allocator) ![]TextEdit {
        const refs = try self.references(uri, name, allocator);
        defer allocator.free(refs);
        const edits = try allocator.alloc(TextEdit, refs.len);
        for (refs, 0..) |reference, index| edits[index] = .{
            .range = .{ .start = .{ .line = reference.line, .character = reference.character }, .end = .{ .line = reference.line, .character = reference.character + @as(u32, @intCast(name.len)) } },
            .replacement = replacement,
        };
        return edits;
    }

    /// Returns concise hover markdown for a declared function/class name.
    pub fn hover(self: *const Server, uri: []const u8, name: []const u8, allocator: std.mem.Allocator) !?[]u8 {
        const symbols = try self.documentSymbols(uri, allocator);
        defer allocator.free(symbols);
        for (symbols) |symbol| if (std.mem.eql(u8, symbol.name, name)) {
            return try std.fmt.allocPrint(allocator, "{s} `{s}`", .{ symbol.kind, symbol.name });
        };
        return null;
    }

    pub fn documentText(self: *const Server, uri: []const u8) ?[]const u8 {
        const index = self.find(uri) orelse return null;
        return self.documents.items[index].text;
    }

    pub fn formatDocument(self: *const Server, uri: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const text = self.documentText(uri) orelse return error.UnknownDocument;
        return formatter.format(allocator, text);
    }

    fn replace(self: *Server, index: usize, text: []const u8, version: i64) !void {
        const owned = try self.allocator.dupe(u8, text);
        self.allocator.free(self.documents.items[index].text);
        self.documents.items[index].text = owned;
        self.documents.items[index].version = version;
        self.documents.items[index].language = (config.languageFromHeader(text) catch .kn) orelse .kn;
    }

    fn find(self: *const Server, uri: []const u8) ?usize {
        for (self.documents.items, 0..) |document, index| if (std.mem.eql(u8, document.uri, uri)) return index;
        return null;
    }
};

test "LSP state applies versioned overlays and compiler diagnostics" {
    var server = Server.init(std.testing.allocator);
    defer server.deinit();
    try server.open("file:///main.rk", "kriya main():\n    kodu 1\n", 1);
    const messages = try server.diagnostics("file:///main.rk", std.testing.allocator);
    defer std.testing.allocator.free(messages);
    try std.testing.expectEqual(@as(usize, 0), messages.len);
    try server.change("file:///main.rk", "function main():\n", 2);
    const changed_messages = try server.diagnostics("file:///main.rk", std.testing.allocator);
    defer std.testing.allocator.free(changed_messages);
    try std.testing.expectEqual(@as(usize, 1), changed_messages.len);
    try std.testing.expectError(error.StaleDocumentVersion, server.change("file:///main.rk", "", 2));
}

test "LSP completion follows the file language profile" {
    var server = Server.init(std.testing.allocator);
    defer server.deinit();
    const completions = try server.completions(.en, std.testing.allocator);
    defer std.testing.allocator.free(completions);
    try std.testing.expectEqualStrings("function", completions[0].label);
}

test "LSP symbols and definitions follow the document language profile" {
    var server = Server.init(std.testing.allocator);
    defer server.deinit();
    try server.open("file:///kn.rk", "kriya main():\n    kodu 1\nroopa Box:\n    bidu\n", 1);
    const kn_symbols = try server.documentSymbols("file:///kn.rk", std.testing.allocator);
    defer std.testing.allocator.free(kn_symbols);
    try std.testing.expectEqual(@as(usize, 2), kn_symbols.len);
    try std.testing.expectEqualStrings("Function", kn_symbols[0].kind);
    try std.testing.expectEqualStrings("Class", kn_symbols[1].kind);
    try std.testing.expect((try server.definition("file:///kn.rk", "main", std.testing.allocator)) != null);

    try server.open("file:///en.rk", "# ravi: language=en\nfunction main():\n    return 1\nclass Box:\n    pass\n", 1);
    const en_symbols = try server.documentSymbols("file:///en.rk", std.testing.allocator);
    defer std.testing.allocator.free(en_symbols);
    try std.testing.expectEqual(@as(usize, 2), en_symbols.len);
    try std.testing.expectEqualStrings("Function", en_symbols[0].kind);
    try std.testing.expectEqualStrings("Class", en_symbols[1].kind);
    try std.testing.expect((try server.definition("file:///en.rk", "Box", std.testing.allocator)) != null);
}
