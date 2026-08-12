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

/// Fixed-capacity set of names visible from a lexical scope, used to tell a
/// genuinely new local variable apart from an intended capture of an
/// enclosing variable when both are merely "assigned, then read" locally.
const NameSet = struct {
    items: [128][]const u8 = undefined,
    count: usize = 0,

    fn contains(self: *const NameSet, name: []const u8) bool {
        for (self.items[0..self.count]) |existing| if (std.mem.eql(u8, existing, name)) return true;
        return false;
    }

    fn add(self: *NameSet, name: []const u8) void {
        if (self.contains(name) or self.count >= self.items.len) return;
        self.items[self.count] = name;
        self.count += 1;
    }

    fn addAll(self: *NameSet, other: *const NameSet) void {
        for (other.items[0..other.count]) |name| self.add(name);
    }
};

/// Collect simple assignment-target names within [first, end), skipping any
/// token range in `skip_ranges` (used to exclude nested function/lambda bodies,
/// which introduce their own scope).
fn collectAssignedNames(tokens: []const lexer.Token, first: usize, end: usize, skip_ranges: []const [2]usize, out: *NameSet) void {
    var i = first;
    while (i < end) {
        var skip_to: ?usize = null;
        for (skip_ranges) |range| if (i >= range[0] and i < range[1]) {
            skip_to = range[1];
            break;
        };
        if (skip_to) |target| {
            i = target;
            continue;
        }
        if (tokens[i].kind == .newline or tokens[i].kind == .indent or tokens[i].kind == .dedent) {
            i += 1;
            continue;
        }
        const line_start = i;
        var line_end = i;
        while (line_end < end and tokens[line_end].kind != .newline and tokens[line_end].kind != .eof) line_end += 1;
        if (tokens[line_start].kind == .identifier) {
            if (line_start + 1 < line_end and tokens[line_start + 1].kind == .operator and std.mem.eql(u8, tokens[line_start + 1].lexeme, "=")) {
                out.add(tokens[line_start].lexeme);
            } else if (line_start + 1 < line_end and tokens[line_start + 1].kind == .colon) {
                var cursor = line_start + 2;
                while (cursor < line_end) : (cursor += 1) {
                    if (tokens[cursor].kind == .operator and std.mem.eql(u8, tokens[cursor].lexeme, "=")) {
                        out.add(tokens[line_start].lexeme);
                        break;
                    }
                }
            }
        }
        i = line_end + 1;
    }
}

/// Refine the naive token-scan capture lists so only names that are actually
/// visible in an enclosing scope remain captures; anything else is a fresh
/// local of the function itself and must not be routed through the closure
/// capture mechanism (which has no slot for it at plain call sites).
pub fn refineLegacyCaptures(allocator: std.mem.Allocator, tokens: []const lexer.Token, declarations: []model.FunctionDecl, class_names: []const []const u8) !void {
    const count = declarations.len;
    if (count == 0) return;
    const parent = try allocator.alloc(?usize, count);
    defer allocator.free(parent);
    for (0..count) |i| {
        parent[i] = null;
        var best_span: usize = std.math.maxInt(usize);
        // Only consider earlier declarations as a possible parent: declarations
        // are discovered in left-to-right token order, so an enclosing function
        // always appears before anything nested in its body. Restricting the
        // search this way also guarantees parent[i] < i, so `visible[parent[i]]`
        // below is always already computed instead of reading uninitialized memory.
        for (0..i) |j| {
            const di = declarations[i];
            const dj = declarations[j];
            if (di.body_first >= dj.body_first and di.body_end <= dj.body_end) {
                const span = dj.body_end - dj.body_first;
                if (span < best_span) {
                    best_span = span;
                    parent[i] = j;
                }
            }
        }
    }

    var top_level_scope = NameSet{};
    {
        var skip_ranges: [256][2]usize = undefined;
        var skip_count: usize = 0;
        for (0..count) |i| if (parent[i] == null and skip_count < skip_ranges.len) {
            skip_ranges[skip_count] = .{ declarations[i].body_first, declarations[i].body_end };
            skip_count += 1;
        };
        collectAssignedNames(tokens, 0, tokens.len, skip_ranges[0..skip_count], &top_level_scope);
        for (declarations) |decl| top_level_scope.add(decl.name);
        for (class_names) |name| top_level_scope.add(name);
    }

    const visible = try allocator.alloc(NameSet, count);
    defer allocator.free(visible);
    for (0..count) |i| {
        const parent_visible = if (parent[i]) |p| visible[p] else top_level_scope;
        var write_index: usize = 0;
        for (declarations[i].captures[0..declarations[i].capture_count]) |capture| {
            if (parent_visible.contains(capture)) {
                declarations[i].captures[write_index] = capture;
                write_index += 1;
            }
        }
        declarations[i].capture_count = write_index;

        var own_locals = NameSet{};
        var skip_ranges: [256][2]usize = undefined;
        var skip_count: usize = 0;
        for (0..count) |j| if (parent[j] != null and parent[j].? == i and skip_count < skip_ranges.len) {
            skip_ranges[skip_count] = .{ declarations[j].body_first, declarations[j].body_end };
            skip_count += 1;
        };
        collectAssignedNames(tokens, declarations[i].body_first, declarations[i].body_end, skip_ranges[0..skip_count], &own_locals);
        var scope = parent_visible;
        scope.addAll(&own_locals);
        for (declarations[i].param_names[0..declarations[i].params_count]) |name| scope.add(name);
        visible[i] = scope;
    }
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
