const std = @import("std");
const Loader = @import("loader.zig").Loader;
const config = @import("ravi_config");
const artifact = @import("ravi_artifact");

test "loader parses imports, orders dependencies, and preserves profiles" {
    const Files = struct {
        fn provide(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
            const source = files.get(path) orelse return error.FileNotFound;
            return allocator.dupe(u8, source);
        }
    };
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "math inda add tago\n");
    try files.put("math.rk", "# ravi: language=en\nfunction add():\n    return 1\n");
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrCast(&files));
    defer loader.deinit();
    const order = try loader.load("app.rk");
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqualStrings("math.rk", loader.module(order[0]).?.path);
    try std.testing.expectEqual(config.SourceLanguage.en, loader.module(order[0]).?.language);
    try std.testing.expectEqualStrings("app.rk", loader.module(order[1]).?.path);
}

test "loader rejects import cycles" {
    const Files = struct {
        fn provide(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
            return allocator.dupe(u8, files.get(path) orelse return error.FileNotFound);
        }
    };
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("a.rk", "b inda x tago\n");
    try files.put("b.rk", "a inda x tago\n");
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrCast(&files));
    defer loader.deinit();
    try std.testing.expectError(error.ImportCycle, loader.load("a.rk"));
}

test "loader searches configured package roots after relative imports" {
    const Files = struct {
        fn provide(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
            return allocator.dupe(u8, files.get(path) orelse return error.FileNotFound);
        }
    };
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "math inda add tago\n");
    const package_path = try std.fs.path.join(std.testing.allocator, &.{ "pkg", "math.rk" });
    defer std.testing.allocator.free(package_path);
    try files.put(package_path, "kriya add():\n    kodu 1\n");
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrCast(&files));
    defer loader.deinit();
    try loader.addSearchPath("pkg");
    const order = try loader.load("app.rk");
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqualStrings(package_path, loader.module(order[0]).?.path);
}

test "loader validates cached interface artifacts" {
    const Files = struct {
        fn provide(_: *anyopaque, allocator: std.mem.Allocator, _: []const u8) ![]u8 {
            return allocator.dupe(u8, "kodu 1\n");
        }
    };
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrFromInt(1));
    defer loader.deinit();
    const bytes = try artifact.encode(std.testing.allocator, "math", "ravi-debug", 0, "exports");
    defer std.testing.allocator.free(bytes);
    var decoded = try loader.decodeArtifact(bytes, .{});
    defer decoded.deinit();
    try std.testing.expectEqualStrings("math", decoded.module_name);
    try std.testing.expectError(error.ResourceLimit, loader.decodeArtifact(bytes, .{ .max_payload_bytes = 2 }));
    try std.testing.expect(try loader.artifactReusable(bytes, "math", "ravi-debug", .kn, .{}));
    try std.testing.expect(!(try loader.artifactReusable(bytes, "math", "ravi-release", .kn, .{})));
    try std.testing.expect(!(try loader.artifactReusable(bytes, "math", "ravi-debug", .en, .{})));
    var corrupt = try std.testing.allocator.dupe(u8, bytes);
    defer std.testing.allocator.free(corrupt);
    corrupt[corrupt.len - 1] ^= 1;
    try std.testing.expect(!(try loader.artifactReusable(corrupt, "math", "ravi-debug", .kn, .{})));
}
