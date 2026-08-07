const std = @import("std");
const formatting = @import("formatting.zig");
const state_helpers = @import("state_helpers.zig");

pub fn string(comptime Error: type, self: anytype, operand: i64, strings: []const []const u8) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(strings.len))) return error.InvalidInstruction;
    const raw = strings[@intCast(operand)];
    if (raw.len < 2) return error.InvalidInstruction;
    const prefixed_raw = raw[0] == 'r' or raw[0] == 'R';
    const quote = raw[if (prefixed_raw) 1 else 0];
    const content_start: usize = if (prefixed_raw) 1 else 0;
    const triple = raw.len >= content_start + 6 and raw[content_start] == quote and raw[content_start + 1] == quote and raw[content_start + 2] == quote;
    const start: usize = if (triple) content_start + 3 else content_start + 1;
    const trim: usize = if (triple) 3 else 1;
    if (raw.len < start + trim) return error.InvalidInstruction;
    const decoded = try self.allocator.alloc(u8, raw.len - start - trim);
    defer self.allocator.free(decoded);
    var out: usize = 0;
    var cursor = start;
    const end = raw.len - trim;
    while (cursor < end) : (cursor += 1) {
        if (!prefixed_raw and raw[cursor] == '\\' and cursor + 1 < end) {
            cursor += 1;
            decoded[out] = switch (raw[cursor]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '\'' => '\'',
                '"' => '"',
                else => raw[cursor],
            };
        } else decoded[out] = raw[cursor];
        out += 1;
    }
    try state_helpers.push(self, try state_helpers.internString(self, decoded[0..out]));
}

pub fn format(comptime Error: type, self: anytype, operand: i64, formats: anytype) Error!void {
    if (operand < 0 or operand >= @as(i64, @intCast(formats.len))) return error.InvalidInstruction;
    const format_info = formats[@intCast(operand)];
    if (self.stack_top < format_info.arg_count) return error.StackUnderflow;
    const first_arg = self.stack_top - format_info.arg_count;
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(self.allocator);
    const estimated_capacity = std.math.add(usize, format_info.template.len, std.math.mul(usize, format_info.arg_count, 16) catch return error.StringTooLong) catch return error.StringTooLong;
    output.ensureTotalCapacity(self.allocator, estimated_capacity) catch return error.OutOfMemory;
    var cursor: usize = if (format_info.template.len > 0 and (format_info.template[0] == 'f' or format_info.template[0] == 'F')) 2 else return error.InvalidInstruction;
    const end = if (format_info.template.len > cursor and format_info.template[format_info.template.len - 1] == format_info.template[cursor - 1]) format_info.template.len - 1 else return error.InvalidInstruction;
    var argument_index: usize = 0;
    while (cursor < end) {
        if (format_info.template[cursor] == '{' and cursor + 1 < end and format_info.template[cursor + 1] == '{') {
            try output.append(self.allocator, '{');
            cursor += 2;
        } else if (format_info.template[cursor] == '}' and cursor + 1 < end and format_info.template[cursor + 1] == '}') {
            try output.append(self.allocator, '}');
            cursor += 2;
        } else if (format_info.template[cursor] == '{') {
            const close = formatting.placeholderEnd(format_info.template, cursor + 1, end) orelse return error.InvalidInstruction;
            if (argument_index >= format_info.arg_count) return error.InvalidInstruction;
            const placeholder = format_info.template[cursor + 1 .. close];
            const spec_start = formatting.specStart(placeholder);
            try formatting.appendValue(&output, self.allocator, self.stack[first_arg + argument_index], self, if (spec_start) |offset| placeholder[offset + 1 ..] else "");
            argument_index += 1;
            cursor = close + 1;
        } else if (format_info.template[cursor] == '}') return error.InvalidInstruction else {
            try output.append(self.allocator, format_info.template[cursor]);
            cursor += 1;
        }
    }
    if (argument_index != format_info.arg_count) return error.InvalidInstruction;
    self.stack[first_arg] = try state_helpers.internString(self, output.items);
    self.stack_top = first_arg + 1;
}
