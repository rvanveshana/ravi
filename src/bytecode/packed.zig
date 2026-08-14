const std = @import("std");

pub const OpCode = enum(u8) { halt, suspend_point, constant, make_string, make_exception, make_function, make_instance, get_property, set_property, load_local, store_local, load_capture, load_capture_ref, store_capture, make_closure, make_array, make_tuple, make_set, make_dict, index, slice, store_index, length, iterable, type_query, string_lower, string_upper, string_strip, string_find, string_replace, string_split, string_join, append_collection, insert_collection, remove_collection, contains_collection, clear_collection, pop_collection, count_collection, reverse_collection, sort_collection, dict_get, dict_put, dict_remove, dict_contains, dict_keys, dict_values, dict_items, set_union, set_intersection, set_difference, range_condition, range_step, dup, guard_integer, guard_float, guard_boolean, guard_string, box_dynamic, unbox_integer, sleep, spawn, wait, print, pop, add, subtract, multiply, divide, modulo, negate, not, equal, not_equal, less, less_equal, greater, greater_equal, logic_and, logic_or, exception_match, jump_if_false, jump, try_begin, try_end, call, call_method, call_super, call_value, return_value, raise_value, true_value, false_value, none_value, make_float, make_format };

pub const Instruction = struct { op: OpCode, operand: i64 = 0 };

pub const PackedInstruction = struct {
    raw: u32,

    pub fn encode(instruction: Instruction) !PackedInstruction {
        if (instruction.operand < -8_388_608 or instruction.operand > 8_388_607) return error.OperandOutOfRange;
        const bits: u32 = @bitCast(@as(i32, @intCast(instruction.operand)) & 0x00ff_ffff);
        return .{ .raw = (@as(u32, @intFromEnum(instruction.op)) << 24) | bits };
    }

    pub fn decode(self: PackedInstruction) !Instruction {
        const opcode = @as(u8, @intCast(self.raw >> 24));
        if (opcode > @intFromEnum(OpCode.make_format)) return error.InvalidOpcode;
        var operand: i32 = @intCast(self.raw & 0x00ff_ffff);
        if ((operand & 0x0080_0000) != 0) operand |= @as(i32, -1) << 24;
        return .{ .op = @enumFromInt(opcode), .operand = operand };
    }
};

pub fn encodePackedCode(allocator: std.mem.Allocator, code: []const Instruction) ![]u8 {
    const bytes = try allocator.alloc(u8, std.math.mul(usize, code.len, 4) catch return error.OutOfMemory);
    errdefer allocator.free(bytes);
    for (code, 0..) |instruction, index| {
        const encoded = try PackedInstruction.encode(instruction);
        const raw = encoded.raw;
        const offset = index * 4;
        bytes[offset] = @truncate(raw);
        bytes[offset + 1] = @truncate(raw >> 8);
        bytes[offset + 2] = @truncate(raw >> 16);
        bytes[offset + 3] = @truncate(raw >> 24);
    }
    return bytes;
}

pub fn decodePackedCode(allocator: std.mem.Allocator, bytes: []const u8) ![]Instruction {
    if (bytes.len % 4 != 0) return error.InvalidInstruction;
    const code = try allocator.alloc(Instruction, bytes.len / 4);
    errdefer allocator.free(code);
    for (code, 0..) |*instruction, index| {
        const offset = index * 4;
        const raw: u32 = @as(u32, bytes[offset]) | (@as(u32, bytes[offset + 1]) << 8) | (@as(u32, bytes[offset + 2]) << 16) | (@as(u32, bytes[offset + 3]) << 24);
        instruction.* = try (PackedInstruction{ .raw = raw }).decode();
    }
    return code;
}
