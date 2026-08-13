const std = @import("std");
const mir = @import("ravi_mir");
const native = @import("ravi_native_backend");

pub const Target = enum { bytecode, native };
pub const Artifact = struct {
    target: Target,
    bytes: []u8,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *Artifact) void {
        self.allocator.free(self.bytes);
    }
};
pub const BackendError = std.mem.Allocator.Error || error{ UnsupportedTarget, EmptyInput };
pub const Backend = struct {
    allocator: std.mem.Allocator,
    target: Target = .bytecode,
    pub fn supportsTarget(target: Target) bool {
        return target == .bytecode or target == .native;
    }
    pub fn lower(self: *Backend, input: []const u8) BackendError!Artifact {
        if (input.len == 0) return error.EmptyInput;
        if (!supportsTarget(self.target)) return error.UnsupportedTarget;
        const bytes = try self.allocator.dupe(u8, input);
        return .{ .target = self.target, .bytes = bytes, .allocator = self.allocator };
    }

    pub fn lowerMir(self: *Backend, function: *const mir.Function) !native.Artifact {
        if (self.target != .native) return error.UnsupportedTarget;
        return native.lower(self.allocator, function);
    }
};

test "backend owns byte artifacts and lowers verified MIR natively" {
    var backend = Backend{ .allocator = std.testing.allocator };
    var artifact = try backend.lower("ravi");
    defer artifact.deinit();
    try std.testing.expectEqualStrings("ravi", artifact.bytes);
    backend.target = .native;
    try std.testing.expect(Backend.supportsTarget(.native));
    try std.testing.expectError(error.UnsupportedTarget, backend.lower("ravi"));
    var function = mir.Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .result = @enumFromInt(0), .result_type = .integer, .source_line = 1, .operation = .{ .constant_integer = 1 } });
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = @enumFromInt(0) } });
    function.value_count = 1;
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 2 });
    var native_artifact = try backend.lowerMir(&function);
    defer native_artifact.deinit();
    try std.testing.expect(std.mem.startsWith(u8, native_artifact.bytes, "RAVI-NATIVE-MIR\n"));
}
