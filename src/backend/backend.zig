const std = @import("std");

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
        return target == .bytecode;
    }
    pub fn lower(self: *Backend, input: []const u8) BackendError!Artifact {
        if (input.len == 0) return error.EmptyInput;
        if (!supportsTarget(self.target)) return error.UnsupportedTarget;
        const bytes = try self.allocator.dupe(u8, input);
        return .{ .target = self.target, .bytes = bytes, .allocator = self.allocator };
    }
};

test "bytecode backend owns its artifact and rejects native placeholder" {
    var backend = Backend{ .allocator = std.testing.allocator };
    var artifact = try backend.lower("ravi");
    defer artifact.deinit();
    try std.testing.expectEqualStrings("ravi", artifact.bytes);
    backend.target = .native;
    try std.testing.expect(!Backend.supportsTarget(.native));
    try std.testing.expectError(error.UnsupportedTarget, backend.lower("ravi"));
}
