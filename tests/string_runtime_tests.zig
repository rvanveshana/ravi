const std = @import("std");
const strings = @import("ravi_vm_strings");

test "UTF-8 indexing and slicing helpers are independently testable" {
    try std.testing.expectEqual(@as(usize, 3), strings.length("AÀB"));
    try std.testing.expectEqual(@as(?usize, 1), strings.offset("AÀB", 1));
    try std.testing.expectEqual(@as(?i64, 0xC0), strings.at("AÀB", 1));
}
