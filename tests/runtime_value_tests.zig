const std = @import("std");
const values = @import("ravi_value");

test "runtime values decode strings and operate on arrays" {
    const decoded = try values.decodeString(std.testing.allocator, "\"a\\nb\"");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("a\nb", decoded);
    var heap = values.Heap.init(std.testing.allocator);
    defer heap.deinit();
    const array = try heap.createArray();
    try heap.append(array, .{ .integer = 9 });
    const element = try values.index(array, 0);
    try std.testing.expectEqual(@as(i64, 9), element.integer);
    try std.testing.expect(values.equal(.{ .string = "ravi" }, .{ .string = "ravi" }));
}
