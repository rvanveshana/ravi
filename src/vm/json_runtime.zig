const std = @import("std");
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const storage = @import("object_storage.zig");
const state = @import("state_helpers.zig");
const collections = @import("ravi_vm_collections");
const max_bytes = 8 * 1024 * 1024;

pub fn decode(vm: anytype, text: []const u8) Error!Value {
    if (text.len > max_bytes) return error.JsonError;
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    try preflight(text);
    const parsed = std.json.parseFromSlice(std.json.Value, vm.allocator, text, .{ .duplicate_field_behavior = .@"error", .max_value_len = max_bytes }) catch |err|
        return if (err == error.OutOfMemory) error.OutOfMemory else error.JsonError;
    defer parsed.deinit();
    const transaction = @import("allocation_transaction.zig").Snapshot.begin(vm);
    errdefer transaction.rollback(vm);
    var nodes: usize = 0;
    return fromJson(vm, parsed.value, 0, &nodes);
}

fn preflight(text: []const u8) Error!void {
    var quoted_string = false;
    var escaped = false;
    var depth: usize = 0;
    var separators: usize = 0;
    for (text) |byte| {
        if (quoted_string) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                quoted_string = false;
            }
        } else switch (byte) {
            '"' => quoted_string = true,
            '[', '{' => {
                depth += 1;
                if (depth > 128) return error.JsonError;
            },
            ']', '}' => {
                if (depth == 0) return error.JsonError;
                depth -= 1;
            },
            ',', ':' => {
                separators += 1;
                if (separators > 65536) return error.JsonError;
            },
            else => {},
        }
    }
}

fn fromJson(vm: anytype, value: std.json.Value, depth: usize, nodes: *usize) Error!Value {
    nodes.* += 1;
    if (depth > 128 or nodes.* > 65536) return error.JsonError;
    return switch (value) {
        .null => Value.nil(),
        .bool => |v| Value.fromBool(v),
        .integer => |v| Value.tryFromInt(v) catch return error.IntegerOutOfRange,
        .float => |v| if (std.math.isFinite(v)) Value.fromFloat(v) else error.JsonError,
        .number_string => |text| blk: {
            const v = std.fmt.parseFloat(f64, text) catch return error.JsonError;
            if (!std.math.isFinite(v)) return error.JsonError;
            break :blk Value.fromFloat(v);
        },
        .string => |v| try state.internString(vm, v),
        .array => |array| blk: {
            const slot = try storage.newArray(vm);
            for (array.items) |child| try collections.append(vm.arrays[slot], try fromJson(vm, child, depth + 1, nodes));
            break :blk Value.fromHandle(.array, slot) catch return error.InvalidInstruction;
        },
        .object => |object| blk: {
            const slot = try storage.newDict(vm);
            var iterator = object.iterator();
            while (iterator.next()) |entry| try collections.put(vm.dicts[slot], try state.internString(vm, entry.key_ptr.*), try fromJson(vm, entry.value_ptr.*, depth + 1, nodes));
            break :blk Value.fromHandle(.dictionary, slot) catch return error.InvalidInstruction;
        },
    };
}

pub fn encode(vm: anytype, value: Value) Error!Value {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(vm.allocator);
    var active: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer active.deinit(vm.allocator);
    try append(vm, value, &output, &active, 0);
    return state.internString(vm, output.items);
}

fn write(vm: anytype, output: *std.ArrayListUnmanaged(u8), text: []const u8) Error!void {
    if (text.len > max_bytes - output.items.len) return error.JsonError;
    output.appendSlice(vm.allocator, text) catch return error.OutOfMemory;
}
fn quoted(vm: anytype, output: *std.ArrayListUnmanaged(u8), text: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    const encoded = std.json.Stringify.valueAlloc(vm.allocator, text, .{}) catch return error.OutOfMemory;
    defer vm.allocator.free(encoded);
    try write(vm, output, encoded);
}
fn append(vm: anytype, value: Value, output: *std.ArrayListUnmanaged(u8), active: *std.AutoHashMapUnmanaged(u64, void), depth: usize) Error!void {
    if (depth > 128) return error.JsonError;
    if (value.isNil()) return write(vm, output, "null");
    if (value.isBool()) return write(vm, output, if (value.asBool()) "true" else "false");
    if (value.isInt() or value.isFloat()) {
        if (value.isFloat() and !std.math.isFinite(value.asFloat())) return error.JsonError;
        var buffer: [128]u8 = undefined;
        const rendered = if (value.isInt()) std.fmt.bufPrint(&buffer, "{d}", .{value.asInt()}) catch return error.JsonError else std.fmt.bufPrint(&buffer, "{d}", .{value.asFloat()}) catch return error.JsonError;
        return write(vm, output, rendered);
    }
    if (value.handleKind() == .string) return quoted(vm, output, vm.stringSlice(value) orelse return error.JsonError);
    if (active.contains(@intFromEnum(value))) return error.JsonError;
    active.put(vm.allocator, @intFromEnum(value), {}) catch return error.OutOfMemory;
    defer _ = active.remove(@intFromEnum(value));
    const slot = value.handleIndex() orelse return error.JsonError;
    if (storage.objectPointer(vm, value) == null) return error.JsonError;
    switch (value.handleKind().?) {
        .array, .tuple => {
            try write(vm, output, "[");
            for (vm.arrays[slot].items[0..vm.arrays[slot].len], 0..) |child, i| {
                if (i != 0) try write(vm, output, ",");
                try append(vm, child, output, active, depth + 1);
            }
            try write(vm, output, "]");
        },
        .dictionary => {
            try write(vm, output, "{");
            var first = true;
            const dict = vm.dicts[slot];
            for (dict.occupied, 0..) |occupied, i| if (occupied) {
                if (!first) try write(vm, output, ",");
                first = false;
                try quoted(vm, output, vm.stringSlice(dict.keys[i]) orelse return error.JsonError);
                try write(vm, output, ":");
                try append(vm, dict.values[i], output, active, depth + 1);
            };
            try write(vm, output, "}");
        },
        else => return error.JsonError,
    }
}
