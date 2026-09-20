const std = @import("std");
const hir = @import("hir.zig");
const Function = hir.Function;
const Type = hir.Type;
const fromName = hir.fromName;

test "HIR retains types guards and source identity" {
    var function = Function.init(std.testing.allocator, "main");
    defer function.deinit();
    const value = try function.appendValue(.integer, .{ .constant_integer = 42 }, 3);
    try function.appendEffect(.{ .guard = .{ .value = value, .expected = .integer } }, 3);
    try function.appendEffect(.{ .return_value = value }, 3);
    try std.testing.expectEqual(@as(usize, 3), function.instructions.items.len);
    try std.testing.expectEqual(@as(usize, 3), function.instructions.items[0].source_line);
}
test "HIR maps supported annotation names explicitly" {
    try std.testing.expectEqual(Type.integer, try fromName("int"));
    try std.testing.expectEqual(Type.string, try fromName("str"));
    try std.testing.expectEqual(Type.dynamic, try fromName("dinamika"));
    try std.testing.expectError(error.UnsupportedType, fromName("kriya"));
    try std.testing.expectError(error.UnsupportedType, fromName("unknown"));
}
test "HIR records resumable suspension source identity" {
    var function = Function.init(std.testing.allocator, "async_main");
    defer function.deinit();
    function.resumable = true;
    function.suspension_count = 1;
    try function.appendEffect(.{ .suspend_point = .{ .resume_line = 12 } }, 12);
    try std.testing.expect(function.resumable);
    try std.testing.expectEqual(@as(usize, 12), function.instructions.items[0].operation.suspend_point.resume_line);
    try std.testing.expectEqual(@as(usize, 1), function.suspension_count);
}
test "HIR rejects parameters outside the declared signature" {
    var function = Function.init(std.testing.allocator, "identity");
    defer function.deinit();
    function.parameter_count = 1;
    _ = try function.appendValue(.integer, .{ .parameter = 1 }, 1);
    try function.setBlocks(&.{.{ .first_instruction = 0, .instruction_count = function.instructions.items.len }});
    try std.testing.expectError(error.InvalidParameter, function.verify());
}
