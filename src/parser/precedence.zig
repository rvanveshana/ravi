const std = @import("std");
const ast = @import("ravi_ast");
const config = @import("ravi_config");

pub fn binaryInfo(parser: anytype) ?struct { op: ast.BinaryOp, left_bp: u8, right_bp: u8 } {
    const raw = parser.tokens[parser.index].lexeme;
    const text = if (parser.tokens[parser.index].kind == .keyword) config.keywordCanonicalFor(parser.language, raw) orelse raw else raw;
    const op: ast.BinaryOp = if (std.mem.eql(u8, text, "or")) .logic_or else if (std.mem.eql(u8, text, "and")) .logic_and else if (std.mem.eql(u8, text, "==")) .equal else if (std.mem.eql(u8, text, "!=")) .not_equal else if (std.mem.eql(u8, text, "<")) .less else if (std.mem.eql(u8, text, "<=")) .less_equal else if (std.mem.eql(u8, text, ">")) .greater else if (std.mem.eql(u8, text, ">=")) .greater_equal else if (std.mem.eql(u8, text, "+")) .add else if (std.mem.eql(u8, text, "-")) .subtract else if (std.mem.eql(u8, text, "*")) .multiply else if (std.mem.eql(u8, text, "/")) .divide else if (std.mem.eql(u8, text, "in")) .in_op else if (std.mem.eql(u8, text, "is")) .is else return null;
    const bp: u8 = switch (op) {
        .logic_or => 10,
        .logic_and => 20,
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .in_op, .is => 30,
        .add, .subtract => 40,
        .multiply, .divide => 50,
    };
    return .{ .op = op, .left_bp = bp, .right_bp = bp + 1 };
}
