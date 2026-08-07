const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const model = @import("model.zig");

pub fn sourceLocation(token: lexer.Token) bytecode.SourceLocation {
    return .{ .start_offset = token.start_offset, .end_offset = token.end_offset, .line = token.line, .column = token.column };
}

pub fn comparisonOpcode(text: []const u8) ?bytecode.OpCode {
    if (std.mem.eql(u8, text, "==")) return .equal;
    if (std.mem.eql(u8, text, "!=")) return .not_equal;
    if (std.mem.eql(u8, text, "<")) return .less;
    if (std.mem.eql(u8, text, "<=")) return .less_equal;
    if (std.mem.eql(u8, text, ">")) return .greater;
    if (std.mem.eql(u8, text, ">=")) return .greater_equal;
    return null;
}

pub fn localSlot(names: *std.ArrayListUnmanaged([]const u8), allocator: std.mem.Allocator, name: []const u8) !usize {
    if (findLocal(names.items, name)) |slot| return slot;
    try names.append(allocator, name);
    return names.items.len - 1;
}

pub fn findLocal(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |existing, i| if (std.mem.eql(u8, existing, name)) return i;
    return null;
}

pub fn findFunction(functions: []const model.FunctionDecl, name: []const u8) ?usize {
    for (functions, 0..) |function, i| if (std.mem.eql(u8, function.name, name)) return i;
    return null;
}

pub fn firstLambda(functions: []const model.FunctionDecl) ?model.FunctionDecl {
    for (functions) |function| if (function.anonymous) return function;
    return null;
}

pub fn findParameter(function: model.FunctionDecl, name: []const u8) ?usize {
    for (function.param_names[0..function.params_count], 0..) |parameter, index| if (std.mem.eql(u8, parameter, name)) return index;
    return null;
}

pub fn findCapture(captures: []const []const u8, name: []const u8) ?usize {
    for (captures, 0..) |capture, index| if (std.mem.eql(u8, capture, name)) return index;
    return null;
}

pub fn argumentCount(tokens: []const lexer.Token) usize {
    if (tokens.len == 0) return 0;
    var count: usize = 1;
    var parens: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    for (tokens) |token| switch (token.kind) {
        .l_paren => parens += 1,
        .r_paren => {
            if (parens > 0) parens -= 1;
        },
        .l_bracket => brackets += 1,
        .r_bracket => {
            if (brackets > 0) brackets -= 1;
        },
        .l_brace => braces += 1,
        .r_brace => {
            if (braces > 0) braces -= 1;
        },
        .comma => {
            if (parens == 0 and brackets == 0 and braces == 0) count += 1;
        },
        else => {},
    };
    return count;
}

pub fn findColon(tokens: []const lexer.Token, start: usize, end: usize) ?usize {
    for (start..end) |i| if (tokens[i].kind == .colon) return i;
    return null;
}

pub fn skipLineTrivia(tokens: []const lexer.Token, start: usize) usize {
    var i = start;
    while (i < tokens.len and (tokens[i].kind == .newline or tokens[i].kind == .comment)) i += 1;
    return i;
}

pub fn skipSuite(tokens: []const lexer.Token, start: usize) usize {
    var i = start;
    var depth: usize = 0;
    while (i < tokens.len) : (i += 1) {
        if (tokens[i].kind == .indent) depth += 1 else if (tokens[i].kind == .dedent) {
            if (depth == 0) return i + 1;
            depth -= 1;
            if (depth == 0) return i + 1;
        }
    }
    return i;
}

pub fn parseRangeCall(tokens: []const lexer.Token) ?model.RangeParts {
    if (tokens.len < 4 or tokens[0].kind != .identifier or
        (!std.mem.eql(u8, tokens[0].lexeme, "range") and !std.mem.eql(u8, tokens[0].lexeme, "shreni")) or
        tokens[1].kind != .l_paren or tokens[tokens.len - 1].kind != .r_paren) return null;
    var result = model.RangeParts{ .args = undefined, .count = 0 };
    var start: usize = 2;
    var nesting: usize = 0;
    var i: usize = 2;
    while (i < tokens.len - 1) : (i += 1) {
        if (tokens[i].kind == .l_paren) nesting += 1 else if (tokens[i].kind == .r_paren) nesting -= 1 else if (tokens[i].kind == .comma and nesting == 0) {
            if (result.count >= 3) return null;
            result.args[result.count] = tokens[start..i];
            result.count += 1;
            start = i + 1;
        }
    }
    if (start < tokens.len - 1) {
        if (result.count >= 3) return null;
        result.args[result.count] = tokens[start .. tokens.len - 1];
        result.count += 1;
    }
    return result;
}
