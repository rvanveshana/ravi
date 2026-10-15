const std = @import("std");
const Loader = @import("ravi_loader").Loader;
const Linker = @import("ravi_linker").Linker;
const Pipeline = @import("ravi_pipeline").Pipeline;
const Vm = @import("ravi_vm").Vm;

const Files = struct {
    fn read(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
        return allocator.dupe(u8, files.get(path) orelse return error.FileNotFound);
    }
};

fn execute(files: *std.StringHashMap([]const u8), root: []const u8) !i64 {
    var loader = Loader.init(std.testing.allocator, Files.read, @ptrCast(files));
    defer loader.deinit();
    const order = try loader.load(root);
    defer std.testing.allocator.free(order);
    var linker = Linker{ .allocator = std.testing.allocator };
    defer linker.deinit();
    var module = try linker.link(&loader, order);
    defer module.deinit();
    var pipeline = Pipeline{ .allocator = std.testing.allocator };
    var chunk = try pipeline.compile(&module);
    defer chunk.deinit();
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    return vm.run(&chunk);
}

test "modules retain profiles and isolate identically named helpers" {
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("left.rk", "# ravi: language=en\nfunction helper():\n    return 1\nfunction left():\n    return helper()\n");
    try files.put("right.rk", "kriya helper():\n    kodu 2\nkriya right():\n    kodu helper()\n");
    try files.put("app.rk", "left inda left tago\nright inda right tago\nleft() * 10 + right()\n");
    try std.testing.expectEqual(@as(i64, 12), try execute(&files, "app.rk"));
}

test "parameters and local assignments can shadow imported names" {
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("math.rk", "kriya answer():\n    kodu 42\n");
    try files.put("app.rk", "math inda answer tago\nkriya identity(answer):\n    kodu answer\nkriya local():\n    answer = 3\n    kodu answer\nidentity(7) + local() + answer()\n");
    try std.testing.expectEqual(@as(i64, 52), try execute(&files, "app.rk"));
}

test "missing modules symbols and private imports are compilation errors" {
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "missing inda x tago\n1\n");
    try std.testing.expectError(error.FileNotFound, execute(&files, "app.rk"));
    try files.put("app.rk", "math inda x tago\n1\n");
    try files.put("math.rk", "mudrisu(1)\n");
    try std.testing.expectError(error.MissingSymbol, execute(&files, "app.rk"));
    try files.put("math.rk", "swanta kriya x():\n    kodu 1\n");
    try std.testing.expectError(error.PrivateSymbol, execute(&files, "app.rk"));
}

test "root profile overrides are respected by module loading" {
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "function square(x: int):\n    return x * x\nsquare(6)\n");
    var loader = Loader.init(std.testing.allocator, Files.read, @ptrCast(&files));
    defer loader.deinit();
    loader.root_language = .en;
    const order = try loader.load("app.rk");
    defer std.testing.allocator.free(order);
    var linker = Linker{ .allocator = std.testing.allocator };
    defer linker.deinit();
    var module = try linker.link(&loader, order);
    defer module.deinit();
    var pipeline = Pipeline{ .allocator = std.testing.allocator };
    var chunk = try pipeline.compile(&module);
    defer chunk.deinit();
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 36), try vm.run(&chunk));
}

test "diamond dependencies initialize once and retain source identities" {
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("leaf.rk", "kriya answer():\n    kodu 42\n");
    try files.put("left.rk", "leaf inda answer tago\nkriya left():\n    kodu answer()\n");
    try files.put("right.rk", "leaf inda answer tago\nkriya right():\n    kodu answer()\n");
    try files.put("app.rk", "left inda left tago\nright inda right tago\nleft() + right()\n");
    var loader = Loader.init(std.testing.allocator, Files.read, @ptrCast(&files));
    defer loader.deinit();
    const order = try loader.load("./app.rk");
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(@as(usize, 4), order.len);
    var linker = Linker{ .allocator = std.testing.allocator };
    defer linker.deinit();
    var module = try linker.link(&loader, order);
    defer module.deinit();
    var pipeline = Pipeline{ .allocator = std.testing.allocator };
    var chunk = try pipeline.compile(&module);
    defer chunk.deinit();
    var sources: [4]bool = @splat(false);
    for (chunk.source_map.items) |location| sources[location.source_id] = true;
    for (sources) |present| try std.testing.expect(present);
    var vm = try Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectEqual(@as(i64, 84), try vm.run(&chunk));
}

test "forward inheritance resolves without reading unpublished class metadata" {
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "roopa Child guru Parent:\n    kodu none\nroopa Parent:\n    kriya answer():\n        kodu 42\nchild = Child()\nchild.answer()\n");
    try std.testing.expectEqual(@as(i64, 42), try execute(&files, "app.rk"));
    try files.put("app.rk", "roopa A guru B:\n    kodu none\nroopa B guru A:\n    kodu none\n");
    try std.testing.expectError(error.InvalidFunction, execute(&files, "app.rk"));
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    const Provider = struct {
        fn read(_: *anyopaque, memory: std.mem.Allocator, path: []const u8) ![]u8 {
            const source = if (std.mem.eql(u8, path, "app.rk")) "math inda answer tago\nanswer()\n" else if (std.mem.eql(u8, path, "math.rk")) "kriya answer():\n    kodu 42\n" else return error.FileNotFound;
            return memory.dupe(u8, source);
        }
    };
    var loader = Loader.init(allocator, Provider.read, @ptrFromInt(1));
    defer loader.deinit();
    try loader.addSearchPath("lib");
    const order = try loader.load("app.rk");
    defer allocator.free(order);
    var linker = Linker{ .allocator = allocator };
    defer linker.deinit();
    var module = try linker.link(&loader, order);
    defer module.deinit();
    var pipeline = Pipeline{ .allocator = allocator };
    var chunk = try pipeline.compile(&module);
    defer chunk.deinit();
}

test "module loading linking and compilation clean up allocation failures" {
    // In-place resizing depends on the backing allocator's current page layout.
    // Disable it so every failure sweep has the same allocation sequence.
    const Deterministic = struct {
        fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
            return std.testing.allocator.rawAlloc(len, alignment, ra);
        }
        fn free(_: *anyopaque, bytes: []u8, alignment: std.mem.Alignment, ra: usize) void {
            std.testing.allocator.rawFree(bytes, alignment, ra);
        }
    };
    const allocator: std.mem.Allocator = .{ .ptr = @ptrFromInt(1), .vtable = &.{
        .alloc = Deterministic.alloc,
        .resize = std.mem.Allocator.noResize,
        .remap = std.mem.Allocator.noRemap,
        .free = Deterministic.free,
    } };
    try std.testing.checkAllAllocationFailures(allocator, allocationExercise, .{});
}
