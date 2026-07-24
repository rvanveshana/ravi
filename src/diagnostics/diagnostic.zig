const std = @import("std");
const source_mod = @import("ravi_source");

pub const SourceId = source_mod.SourceId;
pub const Severity = enum { info, warning, err };

pub const Span = struct {
    source: SourceId = @enumFromInt(0),
    start_offset: usize,
    end_offset: usize,
    line: usize,
    column: usize,
};

pub const Fix = struct {
    span: Span,
    replacement: []const u8,
};

pub const Diagnostic = struct {
    code: []const u8,
    severity: Severity,
    message: []const u8,
    primary: Span,
    note: ?[]const u8 = null,
    fix: ?Fix = null,
};

pub fn severityName(severity: Severity) []const u8 {
    return switch (severity) {
        .info => "info",
        .warning => "warning",
        .err => "error",
    };
}

/// Produces a deterministic source-oriented diagnostic suitable for the CLI
/// and golden tests. Protocol adapters can serialize the same Diagnostic
/// structure without parsing this text.
pub fn renderHuman(allocator: std.mem.Allocator, source_name: []const u8, source: []const u8, diagnostic: Diagnostic) ![]u8 {
    const start = @min(diagnostic.primary.start_offset, source.len);
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..start], '\n')) |index| index + 1 else 0;
    const suffix = source[start..];
    const line_end = if (std.mem.indexOfScalar(u8, suffix, '\n')) |index| start + index else source.len;
    const excerpt = source[line_start..line_end];
    const caret_column = @min(diagnostic.primary.column -| 1, excerpt.len);
    const padding = try allocator.alloc(u8, caret_column);
    defer allocator.free(padding);
    @memset(padding, ' ');
    const note = if (diagnostic.note) |value| try std.fmt.allocPrint(allocator, "\nnote: {s}", .{value}) else try allocator.dupe(u8, "");
    defer allocator.free(note);
    return std.fmt.allocPrint(
        allocator,
        "{s}:{d}:{d}: {s}[{s}]: {s}\n{s}\n{s}^{s}\n",
        .{ source_name, diagnostic.primary.line, diagnostic.primary.column, severityName(diagnostic.severity), diagnostic.code, diagnostic.message, excerpt, padding, note },
    );
}

pub fn renderCompact(allocator: std.mem.Allocator, source_name: []const u8, diagnostic: Diagnostic) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}:{d}:{d}: {s}[{s}]: {s}\n",
        .{ source_name, diagnostic.primary.line, diagnostic.primary.column, severityName(diagnostic.severity), diagnostic.code, diagnostic.message },
    );
}

/// Stable, one-record-per-line representation for editors and build tools.
/// Offsets are byte offsets and the end offset is exclusive.
pub fn renderJson(allocator: std.mem.Allocator, source_name: []const u8, diagnostic: Diagnostic) ![]u8 {
    const escaped_source = try escapeJson(allocator, source_name);
    defer allocator.free(escaped_source);
    const escaped_code = try escapeJson(allocator, diagnostic.code);
    defer allocator.free(escaped_code);
    const escaped_message = try escapeJson(allocator, diagnostic.message);
    defer allocator.free(escaped_message);
    const escaped_note = if (diagnostic.note) |note| try escapeJson(allocator, note) else try allocator.dupe(u8, "");
    defer allocator.free(escaped_note);
    const escaped_replacement = if (diagnostic.fix) |fix| try escapeJson(allocator, fix.replacement) else try allocator.dupe(u8, "");
    defer allocator.free(escaped_replacement);
    const prefix_args = .{ escaped_source, escaped_code, severityName(diagnostic.severity), escaped_message, @intFromEnum(diagnostic.primary.source), diagnostic.primary.start_offset, diagnostic.primary.end_offset, diagnostic.primary.line, diagnostic.primary.column };
    if (diagnostic.fix) |fix| return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":1,\"source\":\"{s}\",\"code\":\"{s}\",\"severity\":\"{s}\",\"message\":\"{s}\",\"span\":{{\"source_id\":{d},\"start\":{d},\"end\":{d},\"line\":{d},\"column\":{d}}},\"note\":{s},\"fix\":{{\"start\":{d},\"end\":{d},\"replacement\":\"{s}\"}}}}\n",
        prefix_args ++ .{ if (diagnostic.note != null) escaped_note else "null", fix.span.start_offset, fix.span.end_offset, escaped_replacement },
    );
    if (diagnostic.note != null) return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":1,\"source\":\"{s}\",\"code\":\"{s}\",\"severity\":\"{s}\",\"message\":\"{s}\",\"span\":{{\"source_id\":{d},\"start\":{d},\"end\":{d},\"line\":{d},\"column\":{d}}},\"note\":\"{s}\"}}\n",
        prefix_args ++ .{escaped_note},
    );
    return std.fmt.allocPrint(
        allocator,
        "{{\"schema\":1,\"source\":\"{s}\",\"code\":\"{s}\",\"severity\":\"{s}\",\"message\":\"{s}\",\"span\":{{\"source_id\":{d},\"start\":{d},\"end\":{d},\"line\":{d},\"column\":{d}}},\"note\":null}}\n",
        prefix_args,
    );
}

fn escapeJson(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(allocator);
    for (value) |byte| switch (byte) {
        '"' => try output.appendSlice(allocator, "\\\""),
        '\\' => try output.appendSlice(allocator, "\\\\"),
        '\n' => try output.appendSlice(allocator, "\\n"),
        '\r' => try output.appendSlice(allocator, "\\r"),
        '\t' => try output.appendSlice(allocator, "\\t"),
        0...8, 11...12, 14...0x1f => {
            var encoded: [6]u8 = undefined;
            const slice = try std.fmt.bufPrint(&encoded, "\\u{x:0>4}", .{byte});
            try output.appendSlice(allocator, slice);
        },
        else => try output.append(allocator, byte),
    };
    return output.toOwnedSlice(allocator);
}

test "human diagnostics include stable code source and caret" {
    const diagnostic = Diagnostic{
        .code = "RAVI-PARSE-001",
        .severity = .err,
        .message = "expected expression",
        .primary = .{ .start_offset = 4, .end_offset = 5, .line = 1, .column = 5 },
        .note = "add a value after '='",
    };
    const rendered = try renderHuman(std.testing.allocator, "sample.rk", "x = \n", diagnostic);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "RAVI-PARSE-001") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "sample.rk:1:5") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "note:") != null);
}

test "compact and JSON diagnostics are deterministic and escaped" {
    const diagnostic = Diagnostic{
        .code = "RAVI-LEX-001",
        .severity = .err,
        .message = "bad \"token\"",
        .primary = .{ .start_offset = 2, .end_offset = 3, .line = 2, .column = 1 },
        .note = "use\ntext",
    };
    const compact = try renderCompact(std.testing.allocator, "sample.rk", diagnostic);
    defer std.testing.allocator.free(compact);
    try std.testing.expectEqualStrings("sample.rk:2:1: error[RAVI-LEX-001]: bad \"token\"\n", compact);
    const json = try renderJson(std.testing.allocator, "sample.rk", diagnostic);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"schema\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "bad \\\"token\\\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "use\\ntext") != null);
}

test "JSON diagnostics preserve fix-it actions" {
    const diagnostic = Diagnostic{
        .code = "RAVI-PARSE-002",
        .severity = .err,
        .message = "missing name",
        .primary = .{ .start_offset = 0, .end_offset = 1, .line = 1, .column = 1 },
        .fix = .{
            .span = .{ .start_offset = 0, .end_offset = 1, .line = 1, .column = 1 },
            .replacement = "name\"value",
        },
    };
    const json = try renderJson(std.testing.allocator, "sample.rk", diagnostic);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fix\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "name\\\"value") != null);
}
