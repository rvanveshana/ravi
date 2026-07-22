const std = @import("std");

pub fn push(self: anytype, value: i64) !void {
    if (self.stack_top == self.stack.len) return error.StackOverflow;
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

pub fn handleFault(self: anytype, ip: *usize) bool {
    if (!self.handler_active) return false;
    self.last_exception = 1;
    self.handler_active = false;
    ip.* = if (self.handler_ip == 0) 0 else self.handler_ip - 1;
    return true;
}

pub fn internString(self: anytype, text: []const u8) !i64 {
    if (text.len > 255) return error.StringTooLong;
    for (0..self.string_count) |existing| if (std.mem.eql(u8, self.strings[existing][0..self.string_lengths[existing]], text)) return -@as(i64, @intCast(2000 + existing));
    if (self.string_count >= self.strings.len) return error.StringTooLong;
    const slot = self.string_count;
    @memcpy(self.strings[slot][0..text.len], text);
    self.string_lengths[slot] = text.len;
    self.string_count += 1;
    return -@as(i64, @intCast(2000 + slot));
}
