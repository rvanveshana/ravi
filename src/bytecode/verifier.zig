const std = @import("std");

pub const VerifyError = error{ OutOfMemory, EmptyChunk, InvalidJump, InvalidLocal, StackUnderflow, InvalidInstruction };

pub fn verify(chunk: anytype) VerifyError!void {
    return verifyWithAllocator(chunk, chunk.allocator);
}

pub fn verifyWithAllocator(chunk: anytype, allocator: std.mem.Allocator) VerifyError!void {
    if (chunk.code.items.len == 0) return error.EmptyChunk;
    if (chunk.source_map.items.len != chunk.code.items.len) return error.InvalidInstruction;
    if (chunk.root_map.items.len != chunk.code.items.len) return error.InvalidInstruction;
    for (chunk.functions.items) |function| {
        if (function.entry == 0 or function.entry >= chunk.code.items.len) return error.InvalidInstruction;
        if (function.arity > function.defaults.len or function.fixed_count > function.arity) return error.InvalidInstruction;
        if (function.varargs_index) |index| if (index >= function.arity) return error.InvalidInstruction;
        if (function.kwargs_index) |index| if (index >= function.arity) return error.InvalidInstruction;
        if ((!function.resumable and function.suspension_count != 0) or (function.resumable and function.suspension_count == 0)) return error.InvalidInstruction;
    }
    for (chunk.captures.items) |capture| if (capture.function >= chunk.functions.items.len) return error.InvalidInstruction;
    for (chunk.classes.items) |class| if (class.base) |base| if (base >= chunk.classes.items.len) return error.InvalidInstruction;
    for (chunk.methods.items) |method| if (method.class_index >= chunk.classes.items.len or method.function_index >= chunk.functions.items.len) return error.InvalidInstruction;
    for (chunk.code.items) |instruction| {
        if (instruction.op == .suspend_point and instruction.operand < 0) return error.InvalidInstruction;
    }
    try verifyFrame(chunk, 0, 0, 0);
    for (chunk.functions.items) |function| try verifyFrame(chunk, function.entry, function.arity + @intFromBool(function.method_name != null), function.capture_count);
    try verifyControlFlow(chunk, allocator);
}

fn verifyFrame(chunk: anytype, first: usize, initial_locals: usize, captures: usize) VerifyError!void {
    var end = chunk.code.items.len;
    for (chunk.functions.items) |function| if (function.entry > first) {
        end = @min(end, function.entry);
    };
    var locals = initial_locals;
    for (chunk.code.items[first..end]) |instruction| if (instruction.op == .store_local) {
        if (instruction.operand < 0 or instruction.operand >= std.math.maxInt(usize)) return error.InvalidLocal;
        locals = @max(locals, @as(usize, @intCast(instruction.operand)) + 1);
    };
    for (chunk.code.items[first..end]) |instruction| switch (instruction.op) {
        .load_local, .load_local_ref => if (instruction.operand < 0 or instruction.operand >= locals) return error.InvalidLocal,
        .load_capture, .load_capture_ref, .store_capture => if (instruction.operand < 0 or instruction.operand >= captures) return error.InvalidLocal,
        else => {},
    };
}

fn verifyControlFlow(chunk: anytype, allocator: std.mem.Allocator) VerifyError!void {
    const depths = allocator.alloc(?isize, chunk.code.items.len) catch return error.OutOfMemory;
    defer allocator.free(depths);
    @memset(depths, null);
    var work: std.ArrayListUnmanaged(struct { instruction: usize, depth: isize }) = .empty;
    defer work.deinit(allocator);
    work.append(allocator, .{ .instruction = 0, .depth = 0 }) catch return error.OutOfMemory;
    for (chunk.functions.items) |function| {
        if (function.entry >= chunk.code.items.len) return error.InvalidInstruction;
        work.append(allocator, .{ .instruction = function.entry, .depth = 0 }) catch return error.OutOfMemory;
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
            .jump => try appendState(chunk, allocator, &work, instruction.operand, next_depth),
            .jump_if_false => {
                try appendState(chunk, allocator, &work, instruction.operand, next_depth);
                if (state.instruction + 1 < chunk.code.items.len) work.append(allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.OutOfMemory;
            },
            .try_begin => {
                try appendState(chunk, allocator, &work, instruction.operand, next_depth + 1);
                if (state.instruction + 1 < chunk.code.items.len) work.append(allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.OutOfMemory;
            },
            .return_value, .halt, .raise_value => {},
            else => if (state.instruction + 1 < chunk.code.items.len) work.append(allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.OutOfMemory,
        }
    }
}

fn appendState(chunk: anytype, allocator: std.mem.Allocator, work: anytype, operand: i64, depth: isize) VerifyError!void {
    if (operand < 0 or operand >= @as(i64, @intCast(chunk.code.items.len))) return error.InvalidJump;
    work.append(allocator, .{ .instruction = @as(usize, @intCast(operand)), .depth = depth }) catch return error.OutOfMemory;
}

fn stackAfter(chunk: anytype, instruction: anytype, depth: isize) VerifyError!isize {
    var required: isize = 0;
    var delta: isize = 0;
    switch (instruction.op) {
        .host_call => {
            if (instruction.operand < 0) return error.InvalidInstruction;
            const id: usize = @intCast(@divTrunc(instruction.operand, 256));
            const args: isize = @intCast(@mod(instruction.operand, 256));
            const config = @import("ravi_config");
            if (id >= config.host_builtins.len or args != config.host_builtins[id].arguments) return error.InvalidInstruction;
            required = args;
            delta = 1 - args;
        },
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
        .make_exception => {
            required = 1;
            delta = 0;
        },
        .make_function => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.functions.items.len))) return error.InvalidInstruction;
            delta = 1;
        },
        .make_instance => {
            if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(chunk.classes.items.len))) return error.InvalidInstruction;
            delta = 1;
        },
        .load_local, .load_local_ref, .load_capture, .load_capture_ref => {
            if (instruction.operand < 0) return error.InvalidLocal;
            delta = 1;
        },
        .store_local, .store_capture, .get_property, .length, .iterable, .type_query, .string_lower, .string_upper, .string_strip, .dict_keys, .dict_values, .dict_items, .negate, .not, .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer, .sleep, .wait => required = 1,
        .spawn => {
            if (instruction.operand < 0 or instruction.operand >= std.math.maxInt(isize)) return error.InvalidInstruction;
            required = @intCast(instruction.operand + 1);
            delta = 1 - required;
        },
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
        .pop_collection => {
            if (instruction.operand < 0 or instruction.operand > 1) return error.InvalidInstruction;
            required = 1 + instruction.operand;
            delta = -instruction.operand;
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
        .exception_match => {
            required = 2;
            delta = -1;
        },
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
