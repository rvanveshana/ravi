const std = @import("std");
const lexer = @import("ravi_lexer");
const bytecode = @import("ravi_bytecode");
const model = @import("model.zig");
const helpers = @import("helpers.zig");

/// Call lowering is isolated from expression parsing. `Compiler` is accepted
/// as `anytype` so this module does not depend on the compiler coordinator and
/// no runtime indirection is introduced.
pub fn emit(self: anytype, chunk: *bytecode.Chunk, tokens: []const lexer.Token, function: model.FunctionDecl, names: *std.ArrayListUnmanaged([]const u8), functions: []const model.FunctionDecl) !void {
    if (function.varargs_index != null or function.kwargs_index != null) return emitVariadic(self, chunk, tokens, function, names, functions);
    var provided: [64]bool = @splat(false);
    var parts: [64][]const lexer.Token = undefined;
    var part_count: usize = 0;
    var start: usize = 0;
    var parens: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    for (tokens, 0..) |token, index| {
        switch (token.kind) {
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
            .comma => if (parens == 0 and brackets == 0 and braces == 0) {
                if (index == start or part_count >= parts.len) return error.InvalidFunction;
                parts[part_count] = tokens[start..index];
                part_count += 1;
                start = index + 1;
            },
            else => {},
        }
    }
    if (start < tokens.len) {
        if (part_count >= parts.len) return error.InvalidFunction;
        parts[part_count] = tokens[start..];
        part_count += 1;
    }
    var positional: usize = 0;
    var saw_keyword = false;
    for (parts[0..part_count]) |part| {
        var equals: ?usize = null;
        for (part, 0..) |token, index| if (token.kind == .operator and std.mem.eql(u8, token.lexeme, "=")) {
            equals = index;
            break;
        };
        if (equals) |equal_index| {
            saw_keyword = true;
            if (equal_index != 1 or part[0].kind != .identifier or equal_index + 1 >= part.len) return error.InvalidFunction;
            const parameter = helpers.findParameter(function, part[0].lexeme) orelse return error.InvalidName;
            if (provided[parameter]) return error.InvalidFunction;
            try self.compileRange(chunk, part[equal_index + 1 ..], names, functions);
            try self.emitParameterGuard(chunk, function.param_types[parameter]);
            provided[parameter] = true;
        } else {
            if (saw_keyword or positional >= function.params_count) return error.InvalidFunction;
            try self.compileRange(chunk, part, names, functions);
            try self.emitParameterGuard(chunk, function.param_types[positional]);
            provided[positional] = true;
            positional += 1;
        }
    }
    for (0..function.params_count) |index| if (!provided[index]) {
        const value = function.defaults[index] orelse return error.InvalidFunction;
        try chunk.emit(.{ .op = .constant, .operand = value });
    };
}

fn emitVariadic(self: anytype, chunk: *bytecode.Chunk, tokens: []const lexer.Token, function: model.FunctionDecl, names: *std.ArrayListUnmanaged([]const u8), functions: []const model.FunctionDecl) !void {
    var fixed: [64]?[]const lexer.Token = @splat(null);
    var extra_pos: [64][]const lexer.Token = undefined;
    var extra_count: usize = 0;
    var extra_names: [64][]const u8 = undefined;
    var extra_values: [64][]const lexer.Token = undefined;
    var keyword_count: usize = 0;
    var positional: usize = 0;
    var parts: [64][]const lexer.Token = undefined;
    var part_count: usize = 0;
    var start: usize = 0;
    for (tokens, 0..) |token, index| if (token.kind == .comma) {
        if (index == start or part_count >= parts.len) return error.InvalidFunction;
        parts[part_count] = tokens[start..index];
        part_count += 1;
        start = index + 1;
    };
    if (start < tokens.len) {
        if (part_count >= parts.len) return error.InvalidFunction;
        parts[part_count] = tokens[start..];
        part_count += 1;
    }
    for (parts[0..part_count]) |part| {
        var equals: ?usize = null;
        for (part, 0..) |token, index| if (token.kind == .operator and std.mem.eql(u8, token.lexeme, "=")) {
            equals = index;
            break;
        };
        if (equals) |equal_index| {
            if (equal_index != 1 or part[0].kind != .identifier or equal_index + 1 >= part.len) return error.InvalidFunction;
            if (helpers.findParameter(function, part[0].lexeme)) |parameter| {
                if (parameter >= function.fixed_count or fixed[parameter] != null) return error.InvalidFunction;
                fixed[parameter] = part[equal_index + 1 ..];
            } else {
                if (function.kwargs_index == null or keyword_count >= extra_names.len) return error.InvalidName;
                extra_names[keyword_count] = part[0].lexeme;
                extra_values[keyword_count] = part[equal_index + 1 ..];
                keyword_count += 1;
            }
        } else if (positional < function.fixed_count) {
            if (fixed[positional] != null) return error.InvalidFunction;
            fixed[positional] = part;
            positional += 1;
        } else {
            if (function.varargs_index == null or extra_count >= extra_pos.len) return error.InvalidFunction;
            extra_pos[extra_count] = part;
            extra_count += 1;
        }
    }
    for (0..function.fixed_count) |index| {
        if (fixed[index]) |expression| {
            try self.compileRange(chunk, expression, names, functions);
            try self.emitParameterGuard(chunk, function.param_types[index]);
        } else if (function.defaults[index]) |value| try chunk.emit(.{ .op = .constant, .operand = value }) else return error.InvalidFunction;
    }
    if (function.varargs_index != null) {
        for (extra_pos[0..extra_count]) |expression| try self.compileRange(chunk, expression, names, functions);
        try chunk.emit(.{ .op = .make_tuple, .operand = @intCast(extra_count) });
    }
    if (function.kwargs_index != null) {
        for (0..keyword_count) |index| {
            const quoted = try self.allocator.alloc(u8, extra_names[index].len + 2);
            quoted[0] = '"';
            @memcpy(quoted[1 .. quoted.len - 1], extra_names[index]);
            quoted[quoted.len - 1] = '"';
            const string_index = try chunk.addString(quoted);
            try chunk.emit(.{ .op = .make_string, .operand = @intCast(string_index) });
            try self.compileRange(chunk, extra_values[index], names, functions);
        }
        try chunk.emit(.{ .op = .make_dict, .operand = @intCast(keyword_count) });
    }
}
