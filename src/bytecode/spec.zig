const std = @import("std");
const packed_bytecode = @import("ravi_packed_bytecode");

pub const OpCode = packed_bytecode.OpCode;

pub const Effect = struct {
    minimum_stack: i64,
    stack_delta: i64,
    terminates: bool = false,
};

pub fn effect(op: OpCode) Effect {
    return switch (op) {
        .halt => .{ .minimum_stack = 0, .stack_delta = 0, .terminates = true },
        .suspend_point => .{ .minimum_stack = 0, .stack_delta = 0 },
        .constant, .make_string, .make_function, .make_instance, .load_local, .load_capture, .load_capture_ref, .true_value, .false_value, .none_value, .make_float => .{ .minimum_stack = 0, .stack_delta = 1 },
        .get_property => .{ .minimum_stack = 1, .stack_delta = 0 },
        .set_property => .{ .minimum_stack = 2, .stack_delta = -2 },
        .store_local, .store_capture => .{ .minimum_stack = 1, .stack_delta = 0 },
        .make_closure => .{ .minimum_stack = 0, .stack_delta = 1 },
        .make_array, .make_tuple, .make_set, .make_dict => .{ .minimum_stack = 0, .stack_delta = 1 },
        .index => .{ .minimum_stack = 2, .stack_delta = -1 },
        .slice => .{ .minimum_stack = 3, .stack_delta = -2 },
        .store_index => .{ .minimum_stack = 3, .stack_delta = -3 },
        .length, .iterable, .type_query, .string_lower, .string_upper, .string_strip, .dict_keys, .dict_values, .dict_items => .{ .minimum_stack = 1, .stack_delta = 0 },
        .string_find, .string_split, .string_join, .contains_collection, .dict_get, .dict_contains, .dict_remove, .set_union, .set_intersection, .set_difference => .{ .minimum_stack = 2, .stack_delta = -1 },
        .string_replace, .insert_collection, .dict_put => .{ .minimum_stack = 3, .stack_delta = -2 },
        .append_collection => .{ .minimum_stack = 2, .stack_delta = -2 },
        .remove_collection => .{ .minimum_stack = 2, .stack_delta = -2 },
        .clear_collection, .pop_collection, .count_collection, .reverse_collection, .sort_collection => .{ .minimum_stack = 1, .stack_delta = 0 },
        .range_condition => .{ .minimum_stack = 3, .stack_delta = -2 },
        .range_step => .{ .minimum_stack = 0, .stack_delta = 0 },
        .dup => .{ .minimum_stack = 1, .stack_delta = 1 },
        .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer, .negate, .not => .{ .minimum_stack = 1, .stack_delta = 0 },
        .sleep => .{ .minimum_stack = 1, .stack_delta = 0 },
        .spawn, .wait => .{ .minimum_stack = 1, .stack_delta = 0 },
        .print, .pop => .{ .minimum_stack = 1, .stack_delta = -1 },
        .add, .subtract, .multiply, .divide, .modulo, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => .{ .minimum_stack = 2, .stack_delta = -1 },
        .make_exception => .{ .minimum_stack = 1, .stack_delta = 0 },
        .exception_match => .{ .minimum_stack = 2, .stack_delta = -1 },
        .jump_if_false => .{ .minimum_stack = 1, .stack_delta = -1 },
        .jump, .try_begin, .try_end => .{ .minimum_stack = 0, .stack_delta = 0 },
        .call, .call_method, .call_super, .call_value => .{ .minimum_stack = 0, .stack_delta = 0 },
        .return_value, .raise_value => .{ .minimum_stack = 1, .stack_delta = -1, .terminates = true },
        .make_format => .{ .minimum_stack = 0, .stack_delta = 1 },
    };
}

pub fn validateAll() void {
    inline for (std.enums.values(OpCode)) |op| {
        _ = effect(op);
    }
}

test "every opcode has a shared effect contract" {
    validateAll();
    try std.testing.expectEqual(@as(i64, -1), effect(.add).stack_delta);
    try std.testing.expect(effect(.return_value).terminates);
    try std.testing.expectEqual(@as(i64, -2), effect(.append_collection).stack_delta);
}
