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

/// A deterministic native ABI lowering record. It is intentionally target
/// neutral: a platform emitter can consume these records without rechecking
/// MIR semantics or inventing a second calling convention.
pub fn lower(allocator: std.mem.Allocator, function: *const mir.Function) !Artifact {
    try contract.verify(function);
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, "RAVI-NATIVE-MIR\n");
    var buffer: [256]u8 = undefined;
    for (function.instructions.items, 0..) |instruction, index| {
        const line = try std.fmt.bufPrint(&buffer, "{d}|{d}|{s}|{s}\n", .{
            index,
            instruction.source_line,
            @tagName(instruction.operation),
            @tagName(instruction.result_type),
        });
        try output.appendSlice(allocator, line);
    }
    return .{ .allocator = allocator, .bytes = try output.toOwnedSlice(allocator) };
}

test "native MIR lowering emits verified ABI records" {
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    const value = try function.appendValue(.integer, .{ .constant_integer = 7 }, 3);
    try function.appendEffect(.{ .return_value = value }, 3);
    try function.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = 2 }});
    var artifact = try lower(std.testing.allocator, &function);
    defer artifact.deinit();
    try std.testing.expect(std.mem.startsWith(u8, artifact.bytes, "RAVI-NATIVE-MIR\n"));
}
