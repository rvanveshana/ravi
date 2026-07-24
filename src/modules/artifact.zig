const std = @import("std");

const magic = "RVMI";
pub const format_version: u16 = 1;
const header_size = 28;

pub const Limits = struct {
    max_name_bytes: usize = 4 * 1024,
    max_key_bytes: usize = 16 * 1024,
    max_payload_bytes: usize = 64 * 1024 * 1024,
};
pub const PayloadKind = enum(u8) { interface = 0, packed_bytecode = 1 };

pub const Interface = struct {
    allocator: std.mem.Allocator,
    module_name: []u8,
    compiler_key: []u8,
    payload: []u8,
    payload_kind: PayloadKind = .interface,
    profile: u8,
    fingerprint: u64,

    pub fn deinit(self: *Interface) void {
        self.allocator.free(self.module_name);
        self.allocator.free(self.compiler_key);
        self.allocator.free(self.payload);
    }
};

pub const ArtifactError = std.mem.Allocator.Error || error{
    InvalidMagic,
    UnsupportedVersion,
    InvalidLength,
    ResourceLimit,
    ChecksumMismatch,
    TrailingData,
};

/// Stable cache key for a module interface or compiled payload. The compiler
/// key and language profile are part of the identity so artifacts cannot be
/// reused across incompatible compiler/runtime configurations.
pub fn interfaceFingerprint(module_name: []const u8, compiler_key: []const u8, profile: u8, payload: []const u8) u64 {
    var value: u64 = 0xcbf29ce484222325;
    hashBytes(&value, module_name);
    hashBytes(&value, compiler_key);
    value ^= profile;
    value *%= 0x100000001b3;
    hashBytes(&value, payload);
    return value;
}

pub fn encode(
    allocator: std.mem.Allocator,
    module_name: []const u8,
    compiler_key: []const u8,
    profile: u8,
    payload: []const u8,
) ArtifactError![]u8 {
    return encodeWithKind(allocator, module_name, compiler_key, profile, .interface, payload);
}

pub fn encodeWithKind(
    allocator: std.mem.Allocator,
    module_name: []const u8,
    compiler_key: []const u8,
    profile: u8,
    payload_kind: PayloadKind,
    payload: []const u8,
) ArtifactError![]u8 {
    try validateLengths(module_name.len, compiler_key.len, payload.len, .{});
    if (payload_kind == .packed_bytecode and payload.len % 4 != 0) return error.InvalidLength;
    const body_len = module_name.len + compiler_key.len + payload.len;
    const output = try allocator.alloc(u8, header_size + body_len);
    errdefer allocator.free(output);
    @memcpy(output[0..4], magic);
    writeInt(output[4..6], format_version);
    output[6] = profile;
    output[7] = @intFromEnum(payload_kind);
    writeInt(output[8..12], @as(u32, @intCast(module_name.len)));
    writeInt(output[12..16], @as(u32, @intCast(compiler_key.len)));
    writeInt(output[16..20], @as(u32, @intCast(payload.len)));
    var cursor: usize = header_size;
    @memcpy(output[cursor .. cursor + module_name.len], module_name);
    cursor += module_name.len;
    @memcpy(output[cursor .. cursor + compiler_key.len], compiler_key);
    cursor += compiler_key.len;
    @memcpy(output[cursor .. cursor + payload.len], payload);
    writeInt(output[20..28], checksum(output[header_size..]));
    return output;
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) ArtifactError!Interface {
    if (bytes.len < header_size) return error.InvalidLength;
    if (!std.mem.eql(u8, bytes[0..4], magic)) return error.InvalidMagic;
    if (readInt(u16, bytes[4..6]) != format_version) return error.UnsupportedVersion;
    if (bytes[7] > @intFromEnum(PayloadKind.packed_bytecode)) return error.InvalidLength;
    const payload_kind: PayloadKind = @enumFromInt(bytes[7]);
    const name_len: usize = readInt(u32, bytes[8..12]);
    const key_len: usize = readInt(u32, bytes[12..16]);
    const payload_len: usize = readInt(u32, bytes[16..20]);
    try validateLengths(name_len, key_len, payload_len, limits);
    if (payload_kind == .packed_bytecode and payload_len % 4 != 0) return error.InvalidLength;
    const expected = std.math.add(usize, header_size, name_len) catch return error.InvalidLength;
    const with_key = std.math.add(usize, expected, key_len) catch return error.InvalidLength;
    const total = std.math.add(usize, with_key, payload_len) catch return error.InvalidLength;
    if (bytes.len < total) return error.InvalidLength;
    if (bytes.len != total) return error.TrailingData;
    if (readInt(u64, bytes[20..28]) != checksum(bytes[header_size..])) return error.ChecksumMismatch;

    const name = try allocator.dupe(u8, bytes[header_size..expected]);
    errdefer allocator.free(name);
    const key = try allocator.dupe(u8, bytes[expected..with_key]);
    errdefer allocator.free(key);
    const payload = try allocator.dupe(u8, bytes[with_key..total]);
    return .{ .allocator = allocator, .module_name = name, .compiler_key = key, .payload = payload, .profile = bytes[6], .payload_kind = payload_kind, .fingerprint = interfaceFingerprint(name, key, bytes[6], payload) };
}

fn validateLengths(name_len: usize, key_len: usize, payload_len: usize, limits: Limits) ArtifactError!void {
    if (name_len == 0) return error.InvalidLength;
    if (name_len > limits.max_name_bytes or key_len > limits.max_key_bytes or payload_len > limits.max_payload_bytes) return error.ResourceLimit;
    if (name_len > std.math.maxInt(u32) or key_len > std.math.maxInt(u32) or payload_len > std.math.maxInt(u32)) return error.ResourceLimit;
}

fn checksum(bytes: []const u8) u64 {
    var value: u64 = 0xcbf29ce484222325;
    for (bytes) |byte| {
        value ^= byte;
        value *%= 0x100000001b3;
    }
    return value;
}

fn hashBytes(value: *u64, bytes: []const u8) void {
    for (bytes) |byte| {
        value.* ^= byte;
        value.* *%= 0x100000001b3;
    }
}

fn writeInt(output: []u8, value: anytype) void {
    var remaining = value;
    for (output) |*byte| {
        byte.* = @truncate(remaining);
        remaining >>= 8;
    }
}

fn readInt(comptime T: type, input: []const u8) T {
    var result: T = 0;
    var index = input.len;
    while (index > 0) {
        index -= 1;
        result = (result << 8) | input[index];
    }
    return result;
}

test "interface artifacts round trip with profile and compiler key" {
    const encoded = try encode(std.testing.allocator, "math", "ravi-0.1-x86_64-debug", 1, "add:int,int->int");
    defer std.testing.allocator.free(encoded);
    var artifact = try decode(std.testing.allocator, encoded, .{});
    defer artifact.deinit();
    try std.testing.expectEqualStrings("math", artifact.module_name);
    try std.testing.expectEqualStrings("ravi-0.1-x86_64-debug", artifact.compiler_key);
    try std.testing.expectEqualStrings("add:int,int->int", artifact.payload);
    try std.testing.expectEqual(@as(u8, 1), artifact.profile);
}

test "interface artifacts reject corruption and configured resource excess" {
    const encoded = try encode(std.testing.allocator, "math", "key", 0, "exports");
    defer std.testing.allocator.free(encoded);
    encoded[encoded.len - 1] ^= 1;
    try std.testing.expectError(error.ChecksumMismatch, decode(std.testing.allocator, encoded, .{}));
    try std.testing.expectError(error.ResourceLimit, decode(std.testing.allocator, encoded, .{ .max_payload_bytes = 2 }));
}

test "artifacts preserve packed bytecode payload kind" {
    const encoded = try encodeWithKind(std.testing.allocator, "math", "ravi-release", 0, .packed_bytecode, "1234");
    defer std.testing.allocator.free(encoded);
    var artifact = try decode(std.testing.allocator, encoded, .{});
    defer artifact.deinit();
    try std.testing.expectEqual(PayloadKind.packed_bytecode, artifact.payload_kind);
}

test "packed artifacts reject non-instruction-aligned payloads" {
    try std.testing.expectError(error.InvalidLength, encodeWithKind(std.testing.allocator, "math", "ravi-release", 0, .packed_bytecode, "bad"));
    const encoded = try encodeWithKind(std.testing.allocator, "math", "ravi-release", 0, .packed_bytecode, "1234");
    defer std.testing.allocator.free(encoded);
    encoded[16] = 5;
    try std.testing.expectError(error.InvalidLength, decode(std.testing.allocator, encoded, .{}));
}

test "interface fingerprints include compiler and profile identity" {
    const first = interfaceFingerprint("math", "ravi-debug", 0, "add");
    try std.testing.expectEqual(first, interfaceFingerprint("math", "ravi-debug", 0, "add"));
    try std.testing.expect(first != interfaceFingerprint("math", "ravi-release", 0, "add"));
    try std.testing.expect(first != interfaceFingerprint("math", "ravi-debug", 1, "add"));
    try std.testing.expect(first != interfaceFingerprint("math", "ravi-debug", 0, "sub"));
}
