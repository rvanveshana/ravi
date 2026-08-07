const std = @import("std");
const ast = @import("ravi_ast");

pub fn formattedPlaceholderEnd(source: []const u8, start: usize, end: usize) ?usize {
    var parentheses: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    var index = start;
    while (index < end) : (index += 1) {
        const character = source[index];
        if (quote != 0) {
            if (escaped) escaped = false else if (character == '\\') escaped = true else if (character == quote) quote = 0;
            continue;
        }
        if (character == '\'' or character == '"') quote = character else if (character == '(') parentheses += 1 else if (character == '[') brackets += 1 else if (character == '{') braces += 1 else if (character == ')' and parentheses > 0) parentheses -= 1 else if (character == ']' and brackets > 0) brackets -= 1 else if (character == '}' and braces > 0) braces -= 1 else if (character == '}' and parentheses == 0 and brackets == 0) return index;
    }
    return null;
}

pub fn formatExpressionEnd(source: []const u8) usize {
    var parentheses: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    for (source, 0..) |character, index| {
        if (quote != 0) {
            if (escaped) escaped = false else if (character == '\\') escaped = true else if (character == quote) quote = 0;
            continue;
        }
        if (character == '\'' or character == '"') quote = character else if (character == '(') parentheses += 1 else if (character == '[') brackets += 1 else if (character == '{') braces += 1 else if (character == ')' and parentheses > 0) parentheses -= 1 else if (character == ']' and brackets > 0) brackets -= 1 else if (character == '}' and braces > 0) braces -= 1 else if (character == ':' and parentheses == 0 and brackets == 0 and braces == 0) return index;
    }
    return source.len;
}

pub fn remapExpressionIds(expression: *ast.Expr, offset: usize) error{InvalidExpression}!void {
    switch (expression.kind) {
        .unary => |*value| value.operand = try remapExpressionId(value.operand, offset),
        .binary => |*value| {
            value.left = try remapExpressionId(value.left, offset);
            value.right = try remapExpressionId(value.right, offset);
        },
        .call => |*value| {
            value.callee = try remapExpressionId(value.callee, offset);
            value.first_arg = try remapExpressionIndex(value.first_arg, offset);
        },
        .assignment => |*value| {
            value.value = try remapExpressionId(value.value, offset);
            if (value.target) |target| value.target = try remapExpressionId(target, offset);
        },
        .member => |*value| value.object = try remapExpressionId(value.object, offset),
        .lambda => |*value| value.body = try remapExpressionId(value.body, offset),
        .array => |*value| value.first = try remapExpressionIndex(value.first, offset),
        .tuple => |*value| value.first = try remapExpressionIndex(value.first, offset),
        .set => |*value| value.first = try remapExpressionIndex(value.first, offset),
        .map => |*value| value.first = try remapExpressionIndex(value.first, offset),
        .index => |*value| {
            value.object = try remapExpressionId(value.object, offset);
            value.index = try remapExpressionId(value.index, offset);
        },
        .slice => |*value| {
            if (value.start) |start| value.start = try remapExpressionId(start, offset);
            if (value.end) |end| value.end = try remapExpressionId(end, offset);
        },
        .formatted_string => return error.InvalidExpression,
        else => {},
    }
}

fn remapExpressionId(value: ast.ExprId, offset: usize) error{InvalidExpression}!ast.ExprId {
    const mapped = std.math.add(usize, @as(usize, value), offset) catch return error.InvalidExpression;
    return @intCast(mapped);
}

fn remapExpressionIndex(value: usize, offset: usize) error{InvalidExpression}!usize {
    return std.math.add(usize, value, offset) catch return error.InvalidExpression;
}
