const std = @import("std");
const mir = @import("ravi_mir");
const contract = @import("ravi_mir_contract");

pub const Artifact = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *Artifact) void {
        self.allocator.free(self.bytes);
    }
};
pub const NativeError = std.mem.Allocator.Error || error{UnsupportedNativeOperation};

/// A deterministic native ABI lowering record. It is intentionally target
/// neutral: a platform emitter can consume these records without rechecking
/// MIR semantics or inventing a second calling convention.
pub fn lower(allocator: std.mem.Allocator, function: *const mir.Function) anyerror!Artifact {
    try contract.verify(function);
    if (function.instructions.items.len != 2) return error.UnsupportedNativeOperation;
    const constant = function.instructions.items[0];
    const returned = function.instructions.items[1];
    const value = switch (constant.operation) {
        .constant_integer => |integer| integer,
        else => return error.UnsupportedNativeOperation,
    };
    const returned_value = switch (returned.operation) {
        .return_value => |result| result,
        else => return error.UnsupportedNativeOperation,
    };
    if (constant.result == null or returned_value == null or @intFromEnum(returned_value.?) != @intFromEnum(constant.result.?)) return error.UnsupportedNativeOperation;
    var bytes = try allocator.alloc(u8, 11);
    bytes[0] = 0x48;
    bytes[1] = 0xb8;
    std.mem.writeInt(u64, bytes[2..10], @bitCast(value), .little);
    bytes[10] = 0xc3;
    return .{ .allocator = allocator, .bytes = bytes };
}

test "native MIR lowering emits executable x86-64 constant return" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    const value = try function.appendValue(.integer, .{ .constant_integer = 7 }, 3);
    try function.appendEffect(.{ .return_value = value }, 3);
    try function.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = 2 }});
    var artifact = try lower(std.testing.allocator, &function);
    defer artifact.deinit();
    try std.testing.expectEqual(@as(usize, 11), artifact.bytes.len);
    try std.testing.expectEqual(@as(u8, 0xc3), artifact.bytes[10]);
}
