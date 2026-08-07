const std = @import("std");
const errors = @import("errors.zig");
const Value = @import("ravi_vm_value").Value;

const RuntimeError = errors.RuntimeError;

pub fn placeholderEnd(template: []const u8, start: usize, end: usize) ?usize {
    var parentheses: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    var index = start;
    while (index < end) : (index += 1) {
        const character = template[index];
        if (quote != 0) {
            if (escaped) escaped = false else if (character == '\\') escaped = true else if (character == quote) quote = 0;
            continue;
        }
        if (character == '\'' or character == '"') quote = character else if (character == '(') parentheses += 1 else if (character == '[') brackets += 1 else if (character == '{') braces += 1 else if (character == ')' and parentheses > 0) parentheses -= 1 else if (character == ']' and brackets > 0) brackets -= 1 else if (character == '}' and braces > 0) braces -= 1 else if (character == '}' and parentheses == 0 and brackets == 0) return index;
    }
    return null;
}

pub fn specStart(placeholder: []const u8) ?usize {
    var parentheses: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var quote: u8 = 0;
    var escaped = false;
    for (placeholder, 0..) |character, index| {
        if (quote != 0) {
            if (escaped) escaped = false else if (character == '\\') escaped = true else if (character == quote) quote = 0;
            continue;
        }
        if (character == '\'' or character == '"') quote = character else if (character == '(') parentheses += 1 else if (character == '[') brackets += 1 else if (character == '{') braces += 1 else if (character == ')' and parentheses > 0) parentheses -= 1 else if (character == ']' and brackets > 0) brackets -= 1 else if (character == '}' and braces > 0) braces -= 1 else if (character == ':' and parentheses == 0 and brackets == 0 and braces == 0) return index;
    }
    return null;
}

fn appendPadding(output: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, count: usize) RuntimeError!void {
    var index: usize = 0;
    while (index < count) : (index += 1) output.append(allocator, ' ') catch return error.OutOfMemory;
}

pub fn appendValue(output: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, value: Value, vm: anytype, spec: []const u8) RuntimeError!void {
    var alignment: u8 = '>';
    var width: usize = 0;
    var type_marker: u8 = 0;
    var cursor: usize = 0;
    if (spec.len > 0 and (spec[0] == '<' or spec[0] == '>' or spec[0] == '^')) {
        alignment = spec[0];
        cursor = 1;
    }
    while (cursor < spec.len and std.ascii.isDigit(spec[cursor])) : (cursor += 1) width = std.math.mul(usize, width, 10) catch return error.StringTooLong;
    if (cursor < spec.len) {
        if (cursor + 1 != spec.len or (spec[cursor] != 's' and spec[cursor] != 'd' and spec[cursor] != 'f')) return error.InvalidInstruction;
        type_marker = spec[cursor];
    }
    if (type_marker == 'd' and !value.isInt()) return error.TypeGuardFailed;
    if (type_marker == 'f' and !value.isFloat() and !value.isInt()) return error.TypeGuardFailed;
    if (type_marker == 's' and (value.handleKind() != .string)) return error.TypeGuardFailed;
    var rendered: std.ArrayListUnmanaged(u8) = .empty;
    defer rendered.deinit(allocator);
    if (value.isNil()) {
        rendered.appendSlice(allocator, "none") catch return error.OutOfMemory;
    } else if (value.isBool()) {
        rendered.appendSlice(allocator, if (value.asBool()) "true" else "false") catch return error.OutOfMemory;
    } else if (value.isInt()) {
        var buffer: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{value.asInt()}) catch return error.StringTooLong;
        rendered.appendSlice(allocator, text) catch return error.OutOfMemory;
    } else if (value.isFloat()) {
        var buffer: [96]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{value.asFloat()}) catch return error.StringTooLong;
        rendered.appendSlice(allocator, text) catch return error.OutOfMemory;
    } else if (value.handleKind() == .string) {
        const text = vm.stringSlice(value) orelse return error.InvalidInstruction;
        rendered.appendSlice(allocator, text) catch return error.OutOfMemory;
    } else {
        rendered.appendSlice(allocator, "<value>") catch return error.OutOfMemory;
    }
    const padding = if (width > rendered.items.len) width - rendered.items.len else 0;
    if (alignment == '<') {
        output.appendSlice(allocator, rendered.items) catch return error.OutOfMemory;
        try appendPadding(output, allocator, padding);
    } else if (alignment == '^') {
        try appendPadding(output, allocator, padding / 2);
        output.appendSlice(allocator, rendered.items) catch return error.OutOfMemory;
        try appendPadding(output, allocator, padding - padding / 2);
    } else {
        try appendPadding(output, allocator, padding);
        output.appendSlice(allocator, rendered.items) catch return error.OutOfMemory;
    }
}
