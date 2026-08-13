const std = @import("std");
const Value = @import("ravi_vm_value").Value;
const collections = @import("ravi_vm_collections");

test "the live NaN-boxed runtime values operate on dynamic arrays" {
    var array = collections.Array.init(std.testing.allocator);
    defer array.deinit();
    try collections.append(&array, Value.fromInt(9));
    try std.testing.expectEqual(@as(i64, 9), array.items[0].asInt());
    try std.testing.expect(Value.eql(Value.fromInt(9), Value.fromFloat(9.0)));
}
