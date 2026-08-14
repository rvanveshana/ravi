const std = @import("std");
const diagnostics = @import("ravi_diagnostics");
const bytecode = @import("ravi_bytecode");

pub const DiagnosticFormat = enum { human, compact, json };

pub fn compilerErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.UnsupportedExpression => "this construct is not supported by the current HIR/MIR lowering path",
        error.InvalidExpression => "the compiler found an invalid expression shape",
        error.InvalidFunction => "the function body is invalid for the current compiler",
        error.InvalidParameter => "the function parameter is invalid in this context",
        else => @errorName(err),
    };
}

pub fn tokenLocation(token: anytype) bytecode.SourceLocation {
    return .{ .start_offset = token.start_offset, .end_offset = token.end_offset, .line = token.line, .column = token.column };
}

pub fn moduleErrorLocation(module: anytype, source: []const u8) bytecode.SourceLocation {
    if (module.statements.items.len == 0) return .{ .start_offset = 0, .end_offset = @min(source.len, 1), .line = 1, .column = 1 };
    const statement = module.statements.items[module.statements.items.len - 1];
    const line = if (statement.span.line == 0) 1 else statement.span.line;
    var offset: usize = 0;
    var current_line: usize = 1;
    while (offset < source.len and current_line < line) : (offset += 1) {
        if (source[offset] == '\n') current_line += 1;
    }
    while (offset < source.len and (source[offset] == ' ' or source[offset] == '\t')) offset += 1;
    return .{ .start_offset = offset, .end_offset = @min(offset + 1, source.len), .line = line, .column = 1 };
}

pub fn print(allocator: std.mem.Allocator, format: DiagnosticFormat, source_name: []const u8, source: []const u8, code: []const u8, message: []const u8, location: bytecode.SourceLocation) void {
    const line = if (location.line == 0) 1 else location.line;
    const offset = sourceOffsetForLine(source, line, location.start_offset);
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..offset], '\n')) |index| index + 1 else 0;
    const diagnostic = diagnostics.Diagnostic{
        .code = code,
        .severity = .err,
        .message = message,
        .primary = .{
            .start_offset = offset,
            .end_offset = @min(offset + @max(location.end_offset -| location.start_offset, 1), source.len),
            .line = line,
            .column = if (location.column == 0) offset - line_start + 1 else location.column,
        },
    };
    const rendered = switch (format) {
        .human => diagnostics.renderHuman(allocator, source_name, source, diagnostic),
        .compact => diagnostics.renderCompact(allocator, source_name, diagnostic),
        .json => diagnostics.renderJson(allocator, source_name, diagnostic),
    } catch {
        std.debug.print("{s}[{s}]: {s}\n", .{ diagnostics.severityName(.err), code, message });
        return;
    };
    defer allocator.free(rendered);
    std.debug.print("{s}", .{rendered});
}

fn sourceOffsetForLine(source: []const u8, line: usize, suggested: usize) usize {
    var current_line: usize = 1;
    var offset: usize = 0;
    while (offset < source.len and current_line < line) : (offset += 1) {
        if (source[offset] == '\n') current_line += 1;
    }
    if (suggested < source.len) {
        var suggested_line: usize = 1;
        for (source[0..suggested]) |character| {
            if (character == '\n') suggested_line += 1;
        }
        if (suggested_line == line) return suggested;
    }
    while (offset < source.len and (source[offset] == ' ' or source[offset] == '\t')) offset += 1;
    return offset;
}
