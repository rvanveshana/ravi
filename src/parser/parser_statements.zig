const std = @import("std");
const ast = @import("ravi_ast");
const config = @import("ravi_config");
const parser_simple_statements = @import("parser_simple_statements.zig");

pub const ParseError = std.mem.Allocator.Error || error{ UnexpectedToken, MissingSuite, InvalidImportOrder, MissingName, InvalidExpression, InvalidNumber, UnterminatedCall };

pub fn parseStatement(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    const start = parser.index;
    var visibility: ast.Visibility = .public;
    if (parser.word("public") or parser.word("private") or parser.word("protected") or parser.word("internal")) {
        visibility = if (parser.word("private")) .private else if (parser.word("protected")) .protected else if (parser.word("internal")) .internal else .public;
        parser.index += 1;
    }

    if (isImportStart(parser)) {
        try parseImport(parser, module, out, start);
    } else if (parser.word("class")) {
        try parseClass(parser, module, out, start, visibility, parseExpressionFn);
    } else if (parser.word("function")) {
        try parseFunction(parser, module, out, start, visibility, parseExpressionFn);
    } else if (parser.word("return") or parser.word("yield")) {
        try parser_simple_statements.parseReturn(parser, module, out, start, parseExpressionFn);
    } else if (parser.word("break") or parser.word("continue") or parser.word("pass") or parser.word("raise")) {
        try parser_simple_statements.parseTransfer(parser, module, out, start, parseExpressionFn);
    } else if (isControl(parser)) {
        try parseControl(parser, module, out, start, parseExpressionFn);
    } else if (parser.at(.identifier) and parser.index + 1 < parser.tokens.len and parser.tokens[parser.index + 1].kind == .colon) {
        try parser_simple_statements.parseTypedAssignment(parser, module, out, start, parseExpressionFn);
    } else {
        const value = try parseExpressionFn(parser, module, 0);
        if (parser.word("with")) {
            parser.index += 1;
            var binding: ?[]const u8 = null;
            if (parser.at(.identifier)) {
                binding = parser.tokens[parser.index].lexeme;
                parser.index += 1;
                if (!parser.word("as")) return error.UnexpectedToken;
                parser.index += 1;
            }
            const body = try parseSuite(parser, module, parseExpressionFn);
            try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .context = .{ .value = value, .binding = binding, .body_first = body.first, .body_count = body.count } } });
            return;
        }
        if (parser.at(.newline)) parser.index += 1;
        try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .expression = value } });
    }
}

fn parseClass(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    visibility: ast.Visibility,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    parser.index += 1;
    if (!parser.at(.identifier)) return error.MissingName;
    const name = parser.tokens[parser.index].lexeme;
    parser.index += 1;
    var base: ?[]const u8 = null;
    if (parser.word("guru")) {
        parser.index += 1;
        if (!parser.at(.identifier)) return error.MissingName;
        base = parser.tokens[parser.index].lexeme;
        parser.index += 1;
    }
    const body = try parseSuite(parser, module, parseExpressionFn);
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .class_decl = .{ .name = name, .base = base, .body_first = body.first, .body_count = body.count, .visibility = visibility } } });
}

fn parseImport(parser: anytype, module: *ast.Module, out: *std.ArrayListUnmanaged(ast.Stmt), start: usize) ParseError!void {
    const module_name = parser.tokens[parser.index].lexeme;
    parser.index += 1;
    if (!parser.word("from")) return error.InvalidImportOrder;
    parser.index += 1;
    const first = module.import_names.items.len;
    while (!parser.at(.newline) and !parser.at(.eof) and !parser.word("import")) {
        if (!parser.at(.identifier) and !parser.at(.comma)) return error.InvalidImportOrder;
        if (parser.at(.identifier)) try module.import_names.append(parser.allocator, parser.tokens[parser.index].lexeme);
        parser.index += 1;
    }
    if (module.import_names.items.len == first or !parser.word("import")) return error.InvalidImportOrder;
    parser.index += 1;
    if (parser.at(.newline)) parser.index += 1;
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .import = .{ .module = module_name, .names_first = first, .names_count = module.import_names.items.len - first } } });
}

fn parseFunction(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    visibility: ast.Visibility,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    parser.index += 1;
    if (!parser.at(.identifier)) return error.MissingName;
    const name = parser.tokens[parser.index].lexeme;
    parser.index += 1;
    const params_first = module.parameters.items.len;
    if (parser.at(.l_paren)) {
        parser.index += 1;
        while (!parser.at(.r_paren)) {
            var parameter_kind: ast.ParameterKind = .positional;
            if (parser.at(.operator) and std.mem.eql(u8, parser.tokens[parser.index].lexeme, "*")) {
                parameter_kind = .variadic;
                parser.index += 1;
                if (parser.at(.operator) and std.mem.eql(u8, parser.tokens[parser.index].lexeme, "*")) {
                    parameter_kind = .keyword_variadic;
                    parser.index += 1;
                }
            }
            if (!parser.at(.identifier)) return error.MissingName;
            const pstart = parser.index;
            const pname = parser.tokens[parser.index].lexeme;
            parser.index += 1;
            var annotation: ?[]const u8 = null;
            if (parser.at(.colon)) {
                parser.index += 1;
                if (!parser.at(.identifier)) return error.MissingName;
                annotation = parser.tokens[parser.index].lexeme;
                parser.index += 1;
            }
            var default_value: ?i64 = null;
            if (parser.at(.operator) and std.mem.eql(u8, parser.tokens[parser.index].lexeme, "=")) {
                parser.index += 1;
                if (!parser.at(.number)) return error.InvalidNumber;
                default_value = std.fmt.parseInt(i64, parser.tokens[parser.index].lexeme, 10) catch return error.InvalidNumber;
                parser.index += 1;
            }
            try module.parameters.append(parser.allocator, .{ .name = pname, .annotation = annotation, .span = .{ .first = pstart, .last = parser.index, .line = parser.tokens[pstart].line }, .default_value = default_value, .kind = parameter_kind });
            if (parser.at(.comma)) parser.index += 1 else if (!parser.at(.r_paren)) return error.UnexpectedToken;
        }
        parser.index += 1;
    }
    const params_count = module.parameters.items.len - params_first;
    var return_type: ?[]const u8 = null;
    if (parser.at(.arrow)) {
        parser.index += 1;
        if (!parser.at(.identifier) and !(parser.at(.keyword) and std.mem.eql(u8, parser.tokens[parser.index].lexeme, "none"))) return error.MissingName;
        return_type = parser.tokens[parser.index].lexeme;
        parser.index += 1;
    }
    const statement_index = out.items.len;
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = start, .line = parser.tokens[start].line }, .kind = .{ .transfer = "pass" } });
    const body = try parseSuite(parser, module, parseExpressionFn);
    out.items[statement_index] = .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .function = .{ .name = name, .params_first = params_first, .params_count = params_count, .return_type = return_type, .body_first = body.first, .body_count = body.count, .decorators_first = 0, .decorators_count = module.decorators.items.len, .visibility = visibility } } };
}

fn parseControl(
    parser: anytype,
    module: *ast.Module,
    out: *std.ArrayListUnmanaged(ast.Stmt),
    start: usize,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!void {
    const keyword = config.keywordCanonicalFor(parser.language, parser.tokens[parser.index].lexeme) orelse parser.tokens[parser.index].lexeme;
    parser.index += 1;
    const statement_index = out.items.len;
    try out.append(parser.allocator, .{ .span = .{ .first = start, .last = start, .line = parser.tokens[start].line }, .kind = .{ .transfer = "" } });
    if (std.mem.eql(u8, keyword, "try")) {
        const body = try parseSuite(parser, module, parseExpressionFn);
        var except_first: usize = 0;
        var except_count: usize = 0;
        var except_binding: ?[]const u8 = null;
        var except_match: ?ast.ExprId = null;
        var finally_first: usize = 0;
        var finally_count: usize = 0;
        if (parser.word("except")) {
            parser.index += 1;
            if (parser.at(.number)) {
                except_match = try parseExpressionFn(parser, module, 0);
            } else if (parser.at(.identifier)) {
                except_binding = parser.tokens[parser.index].lexeme;
                parser.index += 1;
            }
            while (!parser.at(.colon) and !parser.at(.newline) and !parser.at(.eof)) parser.index += 1;
            const except_body = try parseSuite(parser, module, parseExpressionFn);
            except_first = except_body.first;
            except_count = except_body.count;
        }
        if (parser.word("finally")) {
            parser.index += 1;
            const finally_body = try parseSuite(parser, module, parseExpressionFn);
            finally_first = finally_body.first;
            finally_count = finally_body.count;
        }
        out.items[statement_index] = .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .try_stmt = .{ .body_first = body.first, .body_count = body.count, .except_first = except_first, .except_count = except_count, .except_binding = except_binding, .except_match = except_match, .finally_first = finally_first, .finally_count = finally_count } } };
        return;
    }
    if (std.mem.eql(u8, keyword, "for")) {
        if (!parser.at(.identifier)) return error.MissingName;
        const target = parser.tokens[parser.index].lexeme;
        parser.index += 1;
        if (!parser.word("in")) return error.UnexpectedToken;
        parser.index += 1;
        const iterable = try parseExpressionFn(parser, module, 0);
        const body = try parseSuite(parser, module, parseExpressionFn);
        out.items[statement_index] = .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .control = .{ .keyword = keyword, .condition = null, .body_first = body.first, .body_count = body.count, .target = target, .iterable = iterable } } };
        return;
    }
    var condition: ?ast.ExprId = null;
    if (!parser.at(.colon)) condition = try parseExpressionFn(parser, module, 0);
    const body = try parseSuite(parser, module, parseExpressionFn);
    var else_first: usize = 0;
    var else_count: usize = 0;
    if (std.mem.eql(u8, keyword, "if") and parser.word("elif")) {
        else_first = out.items.len;
        try parseControl(parser, module, out, parser.index, parseExpressionFn);
        else_count = out.items.len - else_first;
    } else if ((std.mem.eql(u8, keyword, "if") or std.mem.eql(u8, keyword, "elif")) and parser.word("else")) {
        parser.index += 1;
        const else_body = try parseSuite(parser, module, parseExpressionFn);
        else_first = else_body.first;
        else_count = else_body.count;
    }
    out.items[statement_index] = .{ .span = .{ .first = start, .last = parser.index, .line = parser.tokens[start].line }, .kind = .{ .control = .{ .keyword = keyword, .condition = condition, .body_first = body.first, .body_count = body.count, .else_first = else_first, .else_count = else_count } } };
}

fn parseSuite(
    parser: anytype,
    module: *ast.Module,
    parseExpressionFn: fn (@TypeOf(parser), *ast.Module, u8) ParseError!ast.ExprId,
) ParseError!struct { first: usize, count: usize } {
    if (!parser.at(.colon)) return error.MissingSuite;
    parser.index += 1;
    if (!parser.at(.newline)) return error.MissingSuite;
    parser.index += 1;
    if (!parser.at(.indent)) return error.MissingSuite;
    parser.index += 1;
    const first = module.statements.items.len;
    while (!parser.at(.dedent) and !parser.at(.eof)) {
        while (parser.at(.newline) or parser.at(.comment)) parser.index += 1;
        if (parser.at(.dedent) or parser.at(.eof)) break;
        try parseStatement(parser, module, &module.statements, parseExpressionFn);
    }
    if (parser.at(.dedent)) parser.index += 1;
    return .{ .first = first, .count = module.statements.items.len - first };
}

fn isControl(parser: anytype) bool {
    return parser.word("if") or parser.word("elif") or parser.word("else") or parser.word("while") or parser.word("for") or parser.word("try") or parser.word("except") or parser.word("finally");
}

fn isImportStart(parser: anytype) bool {
    return parser.at(.identifier) and parser.index + 1 < parser.tokens.len and config.keywordCanonicalFor(parser.language, parser.tokens[parser.index + 1].lexeme) != null and std.mem.eql(u8, config.keywordCanonicalFor(parser.language, parser.tokens[parser.index + 1].lexeme).?, "from");
}
