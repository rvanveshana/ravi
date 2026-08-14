const std = @import("std");
const exception_constants = @import("exception_constants.zig");

pub fn message(err: anyerror) []const u8 {
    return exception_constants.messageFor(err);
}

pub fn formatMessage(buffer: []u8, err: anyerror) []const u8 {
    if (exception_constants.fromRuntimeError(err)) |info| {
        return std.fmt.bufPrint(buffer, "{s} ({d}): {s}", .{ info.name, info.code, info.message }) catch info.message;
    }
    return message(err);
}

fn field(vm: anytype, dict: anytype, name: []const u8) ?@TypeOf(dict.values[0]) {
    for (dict.occupied, 0..) |occupied, index| {
        if (occupied) {
            if (vm.stringSlice(dict.keys[index])) |key| {
                if (std.mem.eql(u8, key, name)) return dict.values[index];
            }
        }
    }
    return null;
}

pub fn formatRaised(buffer: []u8, vm: anytype, value: anytype) []const u8 {
    if (value.handleKind() == .exception) {
        const slot = value.handleIndex() orelse return "raised value: <invalid exception object>";
        if (slot >= vm.exception_count) return "raised value: <invalid exception object>";
        const name = vm.exceptions[slot].name;
        if (exception_constants.fromName(name)) |info| return std.fmt.bufPrint(buffer, "{s} ({d}): {s}", .{ info.name, info.code, info.message }) catch info.message;
        return std.fmt.bufPrint(buffer, "raised exception: {s}", .{name}) catch name;
    }
    if (value.handleKind() == .string) {
        const name = vm.stringSlice(value) orelse return "raised value: <invalid exception reference>";
        if (exception_constants.fromName(name)) |info| {
            return std.fmt.bufPrint(buffer, "{s} ({d}): {s}", .{ info.name, info.code, info.message }) catch info.message;
        }
        return std.fmt.bufPrint(buffer, "raised exception: {s}", .{name}) catch name;
    }
    if (value.handleKind() == .dictionary) {
        const slot = value.handleIndex() orelse return "raised value: <runtime object>";
        if (slot < vm.dict_count) {
            const dict = vm.dicts[slot];
            const name_value = field(vm, dict, "name");
            const message_value = field(vm, dict, "message");
            if (name_value) |name| {
                if (message_value) |message_value_unwrapped| {
                    if (vm.stringSlice(name)) |name_text| {
                        if (vm.stringSlice(message_value_unwrapped)) |message_text| {
                            if (field(vm, dict, "code")) |code| {
                                if (code.isInt()) return std.fmt.bufPrint(buffer, "{s} ({d}): {s}", .{ name_text, code.asInt(), message_text }) catch message_text;
                            }
                            return std.fmt.bufPrint(buffer, "{s}: {s}", .{ name_text, message_text }) catch message_text;
                        }
                    }
                }
            }
        }
    }
    if (value.isInt()) {
        if (exception_constants.fromCode(value.asInt())) |info| {
            return std.fmt.bufPrint(buffer, "{s} ({d}): {s}", .{ info.name, info.code, info.message }) catch info.message;
        }
        return std.fmt.bufPrint(buffer, "raised value: {d}", .{value.asInt()}) catch "raised value";
    }
    return "raised value: <runtime object>";
}

pub fn printRaised(vm: anytype, value: anytype) void {
    if (value.isNil()) return;
    var buffer: [512]u8 = undefined;
    std.debug.print("  raised exception: {s}\n", .{formatRaised(&buffer, vm, value)});
}

test "configured numeric exceptions retain their public message" {
    var buffer: [128]u8 = undefined;
    const info = exception_constants.fromCode(511).?;
    const rendered = std.fmt.bufPrint(&buffer, "{s} ({d}): {s}", .{ info.name, info.code, info.message }) catch unreachable;
    try std.testing.expectEqualStrings("ZeroDivisionError (511): division by zero; check the divisor before dividing", rendered);
}
