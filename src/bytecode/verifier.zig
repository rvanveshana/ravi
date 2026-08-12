const std = @import("std");

pub const VerifyError = error{ EmptyChunk, InvalidJump, InvalidLocal, StackUnderflow, InvalidInstruction };

pub fn verify(chunk: anytype) VerifyError!void {
    if (chunk.code.items.len == 0) return error.EmptyChunk;
    if (chunk.source_map.items.len != chunk.code.items.len) return error.InvalidInstruction;
    for (chunk.functions.items) |function| {
        if (function.entry == 0 or function.entry >= chunk.code.items.len) return error.InvalidInstruction;
        if ((!function.resumable and function.suspension_count != 0) or (function.resumable and function.suspension_count == 0)) return error.InvalidInstruction;
    }
    for (chunk.captures.items) |capture| if (capture.function >= chunk.functions.items.len) return error.InvalidInstruction;
    var depth: isize = 0;
    for (chunk.code.items) |instruction| {
        switch (instruction.op) {
            .constant, .make_string, .make_function, .make_instance, .load_local, .load_capture, .load_capture_ref, .true_value, .false_value, .none_value, .make_float => depth += 1,
            .make_format => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.formats.items.len))) return error.InvalidInstruction;
                const argument_count = chunk.formats.items[@intCast(instruction.operand)].arg_count;
                if (argument_count > std.math.maxInt(isize)) return error.InvalidInstruction;
                if (depth < @as(isize, @intCast(argument_count))) return error.StackUnderflow;
                depth -= @as(isize, @intCast(argument_count));
                depth += 1;
            },
            .get_property, .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer => {},
            .suspend_point => if (instruction.operand < 0) return error.InvalidInstruction,
            .make_closure => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
                const captures: isize = @intCast(chunk.functions.items[@intCast(instruction.operand)].capture_count);
                if (depth < captures) return error.StackUnderflow;
                depth += 1 - captures;
            },
            .set_property => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 2;
            },
            .make_array, .make_tuple, .make_set => {
                if (instruction.operand < 0 or depth < instruction.operand) return error.StackUnderflow;
                depth -= instruction.operand;
                depth += 1;
            },
            .make_dict => {
                if (instruction.operand < 0 or instruction.operand > std.math.maxInt(isize) / 2) return error.InvalidInstruction;
                const required = @as(isize, @intCast(instruction.operand)) * 2;
                if (depth < required) return error.StackUnderflow;
                depth -= required;
                depth += 1;
            },
            .index => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .slice => {
                if (depth < 3) return error.StackUnderflow;
                depth -= 2;
            },
            .store_index => {
                if (depth < 3) return error.StackUnderflow;
                depth -= 3;
            },
            .length, .count_collection, .dup => {
                if (depth < 1) return error.StackUnderflow;
                if (instruction.op != .length) depth += 1;
            },
            .string_lower, .string_upper, .string_strip, .type_query => if (depth < 1) return error.StackUnderflow,
            .string_find => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .string_replace => {
                if (depth < 3) return error.StackUnderflow;
                depth -= 2;
            },
            .string_split, .string_join => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .append_collection, .contains_collection => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .insert_collection => {
                if (depth < 3) return error.StackUnderflow;
                depth -= 3;
            },
            .remove_collection => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 2;
            },
            .clear_collection, .pop_collection => if (depth < 1) return error.StackUnderflow,
            .reverse_collection, .sort_collection => {
                if (depth < 1) return error.StackUnderflow;
                depth -= 1;
            },
            .dict_get, .dict_contains => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .dict_put => {
                if (depth < 3) return error.StackUnderflow;
                depth -= 3;
            },
            .dict_remove => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .dict_keys, .dict_values, .dict_items, .iterable => if (depth < 1) return error.StackUnderflow,
            .set_union, .set_intersection, .set_difference => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .range_condition => {
                if (depth < 3) return error.StackUnderflow;
                depth -= 2;
            },
            .range_step => if (instruction.operand < 0 or instruction.operand > std.math.maxInt(isize)) return error.InvalidLocal,
            .print => {
                if (depth < 1) return error.StackUnderflow;
                depth -= 1;
            },
            .store_local => if (instruction.operand < 0 or depth < 1) return error.InvalidLocal,
            .store_capture => if (instruction.operand < 0 or depth < 1) return error.InvalidLocal,
            .pop, .negate, .not, .jump_if_false => {
                if (depth < 1) return error.StackUnderflow;
                if (instruction.op == .pop or instruction.op == .jump_if_false) depth -= 1;
            },
            .add, .subtract, .multiply, .divide, .modulo, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => {
                if (depth < 2) return error.StackUnderflow;
                depth -= 1;
            },
            .call => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
                depth += 1;
            },
            .call_method, .call_super => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
                const arity: isize = @intCast(chunk.functions.items[@intCast(instruction.operand)].arity);
                if (depth < arity + 1) return error.StackUnderflow;
                depth -= arity;
            },
            .call_value => {
                if (instruction.operand < 0 or instruction.operand >= std.math.maxInt(isize)) return error.InvalidInstruction;
                if (depth < instruction.operand + 1) return error.StackUnderflow;
                depth -= instruction.operand;
            },
            .jump => if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.code.items.len))) return error.InvalidJump,
            .try_begin, .try_end, .return_value, .halt => {},
            .raise_value => if (depth < 1) return error.StackUnderflow,
        }
    }
    try verifyControlFlow(chunk);
}

fn verifyControlFlow(chunk: anytype) VerifyError!void {
    const depths = chunk.allocator.alloc(?isize, chunk.code.items.len) catch return error.InvalidInstruction;
    defer chunk.allocator.free(depths);
    @memset(depths, null);
    var work: std.ArrayListUnmanaged(struct { instruction: usize, depth: isize }) = .empty;
    defer work.deinit(chunk.allocator);
    work.append(chunk.allocator, .{ .instruction = 0, .depth = 0 }) catch return error.InvalidInstruction;
    for (chunk.functions.items) |function| {
        if (function.entry >= chunk.code.items.len) return error.InvalidInstruction;
        work.append(chunk.allocator, .{ .instruction = function.entry, .depth = 0 }) catch return error.InvalidInstruction;
    }
    while (work.pop()) |state| {
        if (depths[state.instruction]) |known| {
            if (known != state.depth and chunk.code.items[state.instruction].op != .return_value and chunk.code.items[state.instruction].op != .halt) return error.InvalidInstruction;
            continue;
        }
        depths[state.instruction] = state.depth;
        const instruction = chunk.code.items[state.instruction];
        const next_depth = try stackAfter(chunk, instruction, state.depth);
        switch (instruction.op) {
            .jump => try appendState(chunk, &work, instruction.operand, next_depth),
            .jump_if_false, .try_begin => {
                try appendState(chunk, &work, instruction.operand, next_depth);
                if (state.instruction + 1 < chunk.code.items.len) work.append(chunk.allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.InvalidInstruction;
            },
            .return_value, .halt, .raise_value, .suspend_point => {},
            else => if (state.instruction + 1 < chunk.code.items.len) work.append(chunk.allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.InvalidInstruction,
        }
    }
}

fn appendState(chunk: anytype, work: anytype, operand: i64, depth: isize) VerifyError!void {
    if (operand < 0 or operand >= @as(i64, @intCast(chunk.code.items.len))) return error.InvalidJump;
    work.append(chunk.allocator, .{ .instruction = @as(usize, @intCast(operand)), .depth = depth }) catch return error.InvalidInstruction;
}

fn stackAfter(chunk: anytype, instruction: anytype, depth: isize) VerifyError!isize {
    var required: isize = 0;
    var delta: isize = 0;
    switch (instruction.op) {
        .constant, .true_value, .false_value, .none_value => delta = 1,
        .make_format => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.formats.items.len))) return error.InvalidInstruction;
            const count = chunk.formats.items[@intCast(instruction.operand)].arg_count;
            if (count > std.math.maxInt(isize)) return error.InvalidInstruction;
            required = @intCast(count);
            delta = 1 - required;
        },
        .make_float => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.floats.items.len))) return error.InvalidInstruction;
            delta = 1;
        },
        .make_string => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.strings.items.len))) return error.InvalidInstruction;
            delta = 1;
        },
        .make_function => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
            delta = 1;
        },
        .make_instance => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.classes.items.len))) return error.InvalidInstruction;
            delta = 1;
        },
        .load_local, .load_capture, .load_capture_ref => {
            if (instruction.operand < 0) return error.InvalidLocal;
            delta = 1;
        },
        .store_local, .store_capture, .get_property, .length, .iterable, .type_query, .string_lower, .string_upper, .string_strip, .pop_collection, .dict_keys, .dict_values, .dict_items, .negate, .not, .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer => required = 1,
        .try_begin, .try_end, .jump, .halt, .return_value, .suspend_point, .range_step => {},
        .make_closure => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
            required = @intCast(chunk.functions.items[@intCast(instruction.operand)].capture_count);
            delta = 1 - required;
        },
        .dup, .count_collection => {
            required = 1;
            delta = 1;
        },
        .pop, .print, .clear_collection, .reverse_collection, .sort_collection => {
            required = 1;
            delta = -1;
        },
        .set_property, .add, .subtract, .multiply, .divide, .modulo, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or, .index, .string_find, .string_split, .string_join, .append_collection, .contains_collection, .dict_get, .dict_remove, .dict_contains, .set_union, .set_intersection, .set_difference => {
            required = 2;
            delta = -1;
        },
        .slice, .string_replace, .insert_collection, .store_index, .dict_put, .range_condition => {
            required = 3;
            delta = -2;
            if (instruction.op == .insert_collection or instruction.op == .store_index or instruction.op == .dict_put) delta = -3;
        },
        .remove_collection => {
            required = 2;
            delta = -2;
        },
        .make_array, .make_tuple, .make_set => {
            if (instruction.operand < 0) return error.InvalidInstruction;
            required = @intCast(instruction.operand);
            delta = 1 - required;
        },
        .make_dict => {
            if (instruction.operand < 0 or instruction.operand > std.math.maxInt(isize) / 2) return error.InvalidInstruction;
            required = @as(isize, @intCast(instruction.operand)) * 2;
            delta = 1 - required;
        },
        .jump_if_false => {
            required = 1;
            delta = -1;
        },
        .raise_value => required = 1,
        .call => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
            required = @intCast(chunk.functions.items[@intCast(instruction.operand)].arity);
            delta = 1 - required;
        },
        .call_method, .call_super => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
            required = @as(isize, @intCast(chunk.functions.items[@intCast(instruction.operand)].arity)) + 1;
            delta = 1 - required;
        },
        .call_value => {
            if (instruction.operand < 0 or instruction.operand >= std.math.maxInt(isize)) return error.InvalidInstruction;
            required = @as(isize, @intCast(instruction.operand)) + 1;
            delta = 1 - required;
        },
    }
    if (depth < required) return error.StackUnderflow;
    return depth + delta;
}
