const std = @import("std");
const ast = @import("ravi_ast");
const config = @import("ravi_config");

pub const ParseError = std.mem.Allocator.Error || error{ UnexpectedToken, MissingSuite, InvalidImportOrder, MissingName, InvalidExpression, InvalidNumber, UnterminatedCall };

pub fn parseReturn(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    parser.index += 1;
    var value: ?ast.ExprId = null;
    if (!parser.at(.newline) and !parser.at(.dedent) and !parser.at(.eof)) value = try parseExpressionFn(parser, module, 0);
    if (parser.at(.newline)) parser.index += 1;
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .return_stmt = value } });
}

pub fn parseYield(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    parser.index += 1;
    var value: ?ast.ExprId = null;
    if (!parser.at(.newline) and !parser.at(.dedent) and !parser.at(.eof)) value = try parseExpressionFn(parser, module, 0);
    if (parser.at(.newline)) parser.index += 1;
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .yield_stmt = value } });
}

pub fn parseTransfer(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    const keyword = config.keywordCanonicalFor(parser.language, parser.tokens[parser.index].lexeme) orelse parser.tokens[parser.index].lexeme;
    const is_raise = parser.word("raise");
    parser.index += 1;
    if (is_raise) {
        var value: ?ast.ExprId = null;
        if (!parser.at(.newline) and !parser.at(.dedent) and !parser.at(.eof)) value = try parseExpressionFn(parser, module, 0);
        if (parser.at(.newline)) parser.index += 1;
        try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .raise_stmt = value } });
        return;
    }
    if (parser.at(.newline)) parser.index += 1;
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .transfer = keyword } });
}

pub fn parseTypedAssignment(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    const name = parser.tokens[parser.index].lexeme;
    parser.index += 1;
    parser.index += 1;
    if (!parser.at(.identifier)) return error.MissingName;
    const annotation = parser.tokens[parser.index].lexeme;
    parser.index += 1;
    var array_type = false;
    if (parser.at(.l_bracket)) {
        parser.index += 1;
        if (!parser.at(.r_bracket)) return error.UnexpectedToken;
        parser.index += 1;
        array_type = true;
    }
    if (!parser.at(.operator) or !std.mem.eql(u8, parser.tokens[parser.index].lexeme, "=")) return error.UnexpectedToken;
    parser.index += 1;
    const value = try parseExpressionFn(parser, module, 0);
    if (parser.at(.newline)) parser.index += 1;
    const expression = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .assignment = .{ .name = name, .value = value, .annotation = annotation, .array_type = array_type } } });
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .expression = expression } });
}

fn appendExpr(module: *ast.Module, expression: ast.Expr) ParseError!ast.ExprId {
    const id: ast.ExprId = @intCast(module.expressions.items.len);
    try module.expressions.append(module.allocator, expression);
    return id;
}
