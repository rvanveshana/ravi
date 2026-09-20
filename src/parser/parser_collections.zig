const std = @import("std");
const ast = @import("ravi_ast");
const ParseError = @import("parser_expressions.zig").ParseError;

pub fn parse(parser: anytype, module: *ast.Module, expression: anytype, formatted: anytype) ParseError!ast.ExprId {
    const start = parser.index;
    const token = parser.tokens[start];
    const closing: @TypeOf(token.kind) = switch (token.kind) {
        .l_paren => .r_paren,
        .l_bracket => .r_bracket,
        else => .r_brace,
    };
    parser.index += 1;
    var items: std.ArrayListUnmanaged(ast.ExprId) = .empty;
    defer items.deinit(parser.allocator);
    var dictionary: ?bool = null;
    var comma = false;
    while (!parser.at(closing)) {
        try items.append(parser.allocator, try expression(parser, module, 0, formatted));
        if (token.kind == .l_brace) {
            const pair = parser.at(.colon);
            if (dictionary) |previous| {
                if (previous != pair) return error.InvalidExpression;
            }
            dictionary = pair;
            if (pair) {
                parser.index += 1;
                try items.append(parser.allocator, try expression(parser, module, 0, formatted));
            }
        }
        if (parser.at(.comma)) {
            comma = true;
            parser.index += 1;
        } else if (!parser.at(closing)) return error.UnexpectedToken;
    }
    parser.index += 1;
    if (token.kind == .l_paren and items.items.len == 1 and !comma) {
        module.expressions.items[items.items[0]].parenthesized = true;
        return items.items[0];
    }
    const first = module.collection_items.items.len;
    try module.collection_items.appendSlice(parser.allocator, items.items);
    const count = items.items.len;
    const kind: ast.Expr.Kind = switch (token.kind) {
        .l_paren => .{ .tuple = .{ .first = first, .count = count } },
        .l_bracket => .{ .array = .{ .first = first, .count = count } },
        else => if (dictionary orelse true) .{ .map = .{ .first = first, .count = count / 2 } } else .{ .set = .{ .first = first, .count = count } },
    };
    const id: ast.ExprId = @intCast(module.expressions.items.len);
    try module.expressions.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = kind });
    return id;
}
