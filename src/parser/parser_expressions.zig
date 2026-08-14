const std = @import("std");
const lexer_mod = @import("ravi_lexer");
const ast = @import("ravi_ast");
const precedence = @import("precedence.zig");
const helpers = @import("helpers.zig");

pub const ParseError = std.mem.Allocator.Error || error{ UnexpectedToken, MissingSuite, InvalidImportOrder, MissingName, InvalidExpression, InvalidNumber, UnterminatedCall };

pub fn parseExpression(
    parser: anytype,
    module: *ast.Module,
    min_bp: u8,
    parseFormattedExpressionFn: fn (@TypeOf(parser), *ast.Module, []const u8, usize, usize) ParseError!ast.ExprId,
) ParseError!ast.ExprId {
    const start = parser.index;
    var left = try parsePrefix(parser, module, parseFormattedExpressionFn);
    while (true) {
        if (parser.at(.operator) and std.mem.eql(u8, parser.tokens[parser.index].lexeme, "=")) {
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
            parser.index += 1;
            const value = try parseExpression(parser, module, 1, parseFormattedExpressionFn);
            left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .assignment = .{ .name = name, .value = value, .target = if (is_member_target) left else null } } });
            continue;
        }
        if (parser.at(.dot)) {
            parser.index += 1;
            if (!parser.at(.identifier)) return error.MissingName;
            const member_name = parser.tokens[parser.index].lexeme;
            parser.index += 1;
            left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .member = .{ .object = left, .name = member_name } } });
            continue;
        }
        if (parser.at(.l_paren)) {
            if (90 < min_bp) break;
            parser.index += 1;
            var arguments: std.ArrayListUnmanaged(ast.ExprId) = .empty;
            var keyword_names: std.ArrayListUnmanaged([]const u8) = .empty;
            defer arguments.deinit(parser.allocator);
            defer keyword_names.deinit(parser.allocator);
            while (!parser.at(.r_paren)) {
                const argument = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
                const argument_kind = module.expressions.items[argument].kind;
                if (argument_kind == .assignment and argument_kind.assignment.target == null) {
                    try keyword_names.append(parser.allocator, argument_kind.assignment.name);
                    try arguments.append(parser.allocator, argument_kind.assignment.value);
                } else try arguments.append(parser.allocator, argument);
                if (parser.at(.comma)) parser.index += 1 else if (!parser.at(.r_paren)) return error.UnterminatedCall;
            }
            parser.index += 1;
            const first_arg = module.call_args.items.len;
            try module.call_args.appendSlice(parser.allocator, arguments.items);
            const keyword_first = module.call_keywords.items.len;
            try module.call_keywords.appendSlice(parser.allocator, keyword_names.items);
            left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .call = .{ .callee = left, .first_arg = first_arg, .arg_count = arguments.items.len, .keyword_first = keyword_first, .keyword_count = keyword_names.items.len } } });
            continue;
        }
        if (parser.at(.l_bracket)) {
            parser.index += 1;
            if (parser.at(.colon)) {
                parser.index += 1;
                const finish = if (parser.at(.r_bracket)) null else try parseExpression(parser, module, 0, parseFormattedExpressionFn);
                if (!parser.at(.r_bracket)) return error.UnexpectedToken;
                parser.index += 1;
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .slice = .{ .object = left, .start = null, .end = finish } } });
                continue;
            }
            const index = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
            if (parser.at(.colon)) {
                parser.index += 1;
                const finish = if (parser.at(.r_bracket)) null else try parseExpression(parser, module, 0, parseFormattedExpressionFn);
                if (!parser.at(.r_bracket)) return error.UnexpectedToken;
                parser.index += 1;
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .slice = .{ .object = left, .start = index, .end = finish } } });
            } else {
                if (!parser.at(.r_bracket)) return error.UnexpectedToken;
                parser.index += 1;
                left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .index = .{ .object = left, .index = index } } });
            }
            continue;
        }
        const info = precedence.binaryInfo(parser) orelse break;
        if (info.left_bp < min_bp) break;
        parser.index += 1;
        const right = try parseExpression(parser, module, info.right_bp, parseFormattedExpressionFn);
        left = try appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .binary = .{ .op = info.op, .left = left, .right = right } } });
    }
    return left;
}

fn parsePrefix(
    parser: anytype,
    module: *ast.Module,
    parseFormattedExpressionFn: fn (@TypeOf(parser), *ast.Module, []const u8, usize, usize) ParseError!ast.ExprId,
) ParseError!ast.ExprId {
    const token = parser.tokens[parser.index];
    const start = parser.index;
    if (parser.word("spawn") or parser.word("wait")) {
        const is_spawn = parser.word("spawn");
        parser.index += 1;
        const operand = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
        return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = if (is_spawn) .{ .spawn = operand } else .{ .wait = operand } });
    }
    if (parser.word("function")) return parseLambda(parser, module, start, parseFormattedExpressionFn);
    if (parser.at(.operator) and (std.mem.eql(u8, token.lexeme, "-") or std.mem.eql(u8, token.lexeme, "+"))) {
        parser.index += 1;
        const operand = try parseExpression(parser, module, 80, parseFormattedExpressionFn);
        if (std.mem.eql(u8, token.lexeme, "+")) return operand;
        return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = .{ .unary = .{ .op = .negate, .operand = operand } } });
    }
    if (parser.word("not")) {
        parser.index += 1;
        const operand = try parseExpression(parser, module, 80, parseFormattedExpressionFn);
        return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = .{ .unary = .{ .op = .not, .operand = operand } } });
    }
    if (token.kind == .string and token.lexeme.len > 1 and (token.lexeme[0] == 'f' or token.lexeme[0] == 'F')) {
        return parseFormattedString(parser, module, start, parseFormattedExpressionFn);
    }
    if (parser.at(.l_paren)) {
        parser.index += 1;
        const first = module.expressions.items.len;
        var count: usize = 0;
        const value = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
        count += 1;
        if (parser.at(.comma)) {
            while (parser.at(.comma)) {
                parser.index += 1;
                _ = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
                count += 1;
            }
            if (!parser.at(.r_paren)) return error.UnexpectedToken;
            parser.index += 1;
            return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = .{ .tuple = .{ .first = first, .count = count } } });
        }
        if (!parser.at(.r_paren)) return error.UnexpectedToken;
        parser.index += 1;
        return value;
    }
    if (parser.at(.l_bracket)) {
        parser.index += 1;
        const first = module.expressions.items.len;
        var count: usize = 0;
        while (!parser.at(.r_bracket)) {
            _ = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
            count += 1;
            if (parser.at(.comma)) parser.index += 1 else if (!parser.at(.r_bracket)) return error.UnexpectedToken;
        }
        parser.index += 1;
        return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = .{ .array = .{ .first = first, .count = count } } });
    }
    if (parser.at(.l_brace)) {
        parser.index += 1;
        const first = module.expressions.items.len;
        var count: usize = 0;
        while (!parser.at(.r_brace)) {
            _ = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
            if (parser.at(.colon)) {
                parser.index += 1;
                _ = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
                count += 1;
            } else count += 1;
            if (parser.at(.comma)) parser.index += 1 else if (!parser.at(.r_brace)) return error.UnexpectedToken;
        }
        parser.index += 1;
        return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = if (count == 0 or parser.tokens[start + 2].kind == .colon) .{ .map = .{ .first = first, .count = count } } else .{ .set = .{ .first = first, .count = count } } });
    }

    parser.index += 1;
    const kind: ast.Expr.Kind = switch (token.kind) {
        .number => if (std.mem.indexOfScalar(u8, token.lexeme, '.') != null) .{ .float = std.fmt.parseFloat(f64, token.lexeme) catch return error.InvalidNumber } else .{ .integer = std.fmt.parseInt(i64, token.lexeme, 10) catch return error.InvalidNumber },
        .string => .{ .string = token.lexeme },
        .identifier => .{ .name = token.lexeme },
        .keyword => if (std.mem.eql(u8, token.lexeme, "true")) .{ .boolean = true } else if (std.mem.eql(u8, token.lexeme, "false")) .{ .boolean = false } else if (std.mem.eql(u8, token.lexeme, "none")) .none else return error.InvalidExpression,
        else => return error.InvalidExpression,
    };
    return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = kind });
}

fn parseFormattedString(
    parser: anytype,
    module: *ast.Module,
    start: usize,
    parseFormattedExpressionFn: fn (@TypeOf(parser), *ast.Module, []const u8, usize, usize) ParseError!ast.ExprId,
) ParseError!ast.ExprId {
    const token = parser.tokens[parser.index];
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
            const expression_id = try parseFormattedExpressionFn(parser, module, expression[0..expression_end], start, token.line);
            try module.format_args.append(parser.allocator, expression_id);
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
    parser.index += 1;
    return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = token.line }, .kind = .{ .formatted_string = .{ .template = raw, .first_arg = first_arg, .arg_count = argument_count } } });
}

fn parseLambda(
    parser: anytype,
    module: *ast.Module,
    start: usize,
    parseFormattedExpressionFn: fn (@TypeOf(parser), *ast.Module, []const u8, usize, usize) ParseError!ast.ExprId,
) ParseError!ast.ExprId {
    parser.index += 1;
    const first = module.parameters.items.len;
    if (!parser.at(.l_paren)) return error.UnexpectedToken;
    parser.index += 1;
    while (!parser.at(.r_paren)) {
        if (!parser.at(.identifier)) return error.MissingName;
        const p = parser.tokens[parser.index];
        parser.index += 1;
        var annotation: ?[]const u8 = null;
        if (parser.at(.colon)) {
            parser.index += 1;
            if (!parser.at(.identifier)) return error.MissingName;
            annotation = parser.tokens[parser.index].lexeme;
            parser.index += 1;
        }
        try module.parameters.append(parser.allocator, .{ .name = p.lexeme, .annotation = annotation, .span = .{ .first = parser.index - 1, .last = parser.index, .line = p.line } });
        if (parser.at(.comma)) parser.index += 1 else if (!parser.at(.r_paren)) return error.UnexpectedToken;
    }
    parser.index += 1;
    if (parser.at(.arrow)) {
        parser.index += 1;
        if (!parser.at(.identifier)) return error.MissingName;
        parser.index += 1;
    }
    if (!parser.at(.fat_arrow)) return error.MissingSuite;
    parser.index += 1;
    const body = try parseExpression(parser, module, 0, parseFormattedExpressionFn);
    return appendExpr(module, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .lambda = .{ .params_first = first, .params_count = module.parameters.items.len - first, .body = body } } });
}

fn appendExpr(module: *ast.Module, expression: ast.Expr) ParseError!ast.ExprId {
    const id: ast.ExprId = @intCast(module.expressions.items.len);
    try module.expressions.append(module.allocator, expression);
    return id;
}
