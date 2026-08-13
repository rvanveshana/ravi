const std = @import("std");
const mir = @import("ravi_mir");
const bytecode = @import("ravi_bytecode");

const PendingJump = struct { instruction: usize, target: mir.BlockId };

pub fn emitBody(chunk: *bytecode.Chunk, function: *const mir.Function) !void {
    var block_offsets = try chunk.allocator.alloc(usize, function.blocks.items.len);
    defer chunk.allocator.free(block_offsets);
    var pending: std.ArrayListUnmanaged(PendingJump) = .empty;
    defer pending.deinit(chunk.allocator);
    for (function.blocks.items, 0..) |block, block_index| {
        block_offsets[block_index] = chunk.code.items.len;
        const end = block.first_instruction + block.instruction_count;
        for (block.first_instruction..end) |instruction_index| {
            const instruction = function.instructions.items[instruction_index];
            const emitted_start = chunk.code.items.len;
            chunk.setSourceLocation(.{ .start_offset = 0, .end_offset = 0, .line = instruction.source_line, .column = 0 });
            try emitInstruction(chunk, function, instruction, block_index, &pending);
            try chunk.setRootMetadata(emitted_start, .{ .local_slots = function.parameter_count + function.local_count + function.value_count });
        }
    }
    for (pending.items) |jump| {
        const target_index = @intFromEnum(jump.target);
        if (target_index >= block_offsets.len or jump.instruction >= chunk.code.items.len) return error.InvalidBlock;
        chunk.code.items[jump.instruction].operand = @intCast(block_offsets[target_index]);
    }
}

fn emitPhiEdge(chunk: *bytecode.Chunk, function: *const mir.Function, source_block: usize, target: mir.BlockId) !void {
    const target_index = @intFromEnum(target);
    if (target_index >= function.blocks.items.len) return error.InvalidBlock;
    const block = function.blocks.items[target_index];
    const end = block.first_instruction + block.instruction_count;
    for (function.instructions.items[block.first_instruction..end]) |instruction| {
        const inputs = switch (instruction.operation) {
            .phi => |value| value,
            else => break,
        };
        const result = instruction.result orelse return error.InvalidPhi;
        var selected: ?mir.ValueId = null;
        for (inputs) |input| {
            if (@intFromEnum(input.block) == source_block) selected = input.value;
        }
        const value = selected orelse return error.InvalidPhi;
        try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value)) });
        try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
    }
}

fn emitInstruction(chunk: *bytecode.Chunk, function: *const mir.Function, instruction: mir.Instruction, source_block: usize, pending: *std.ArrayListUnmanaged(PendingJump)) !void {
    const localOffset = function.parameter_count + function.value_count;
    switch (instruction.operation) {
        .constant_integer => |value| {
            try chunk.emit(.{ .op = .constant, .operand = value });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .constant_float => |value| {
            const index = try chunk.addFloat(value);
            try chunk.emit(.{ .op = .make_float, .operand = @intCast(index) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .constant_string => |value| {
            const index = try chunk.addString(value);
            try chunk.emit(.{ .op = .make_string, .operand = @intCast(index) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .constant_boolean => |value| {
            try chunk.emit(.{ .op = if (value) .true_value else .false_value });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .constant_none => {
            try chunk.emit(.{ .op = .none_value });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .unary => |unary| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(unary.operand)) });
            try chunk.emit(.{ .op = if (unary.operator == .negate) .negate else .not });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .parameter => |slot| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(slot) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .load_local => |slot| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(localOffset + slot) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .load_capture => |slot| {
            try chunk.emit(.{ .op = .load_capture, .operand = @intCast(slot) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .load_capture_ref => |slot| {
            try chunk.emit(.{ .op = .load_capture_ref, .operand = @intCast(slot) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .store_capture => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.value)) });
            try chunk.emit(.{ .op = .store_capture, .operand = @intCast(value.slot) });
        },
        .store_local => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.value)) });
            try chunk.emit(.{ .op = .store_local, .operand = @intCast(localOffset + value.slot) });
        },
        .bind_exception => |slot| {
            try chunk.emit(.{ .op = .store_local, .operand = @intCast(localOffset + slot) });
            try chunk.emit(.{ .op = .pop });
        },
        .phi => {},
        .guard => |guard| try chunk.emit(.{ .op = switch (guard.expected) {
            .integer => .guard_integer,
            .float => .guard_float,
            .boolean => .guard_boolean,
            .string => .guard_string,
            .none, .dynamic => return error.UnsupportedMIR,
        } }),
        .binary => |binary| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(binary.left)) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(binary.right)) });
            try chunk.emit(.{ .op = switch (binary.operator) {
                .add => .add,
                .subtract => .subtract,
                .multiply => .multiply,
                .divide => .divide,
                .modulo => .modulo,
                .equal => .equal,
                .not_equal => .not_equal,
                .less => .less,
                .less_equal => .less_equal,
                .greater => .greater,
                .greater_equal => .greater_equal,
                .logic_and => .logic_and,
                .logic_or => .logic_or,
            } });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .call => |call| {
            for (call.arguments) |argument| try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(argument)) });
            try chunk.emit(.{ .op = .call, .operand = @intCast(call.function) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .call_value => |call| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(call.callee)) });
            for (call.arguments) |argument| try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(argument)) });
            try chunk.emit(.{ .op = .call_value, .operand = @intCast(call.arguments.len) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .make_function => |function_index| {
            try chunk.emit(.{ .op = .make_function, .operand = @intCast(function_index) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .make_closure => |closure| {
            for (closure.captures) |capture| try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(capture)) });
            try chunk.emit(.{ .op = .make_closure, .operand = @intCast(closure.function) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .make_instance => |class_index| {
            try chunk.emit(.{ .op = .make_instance, .operand = @intCast(class_index) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .make_array, .make_tuple, .make_set, .make_dict => |values| {
            for (values) |value| try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value)) });
            const operation: bytecode.OpCode = switch (instruction.operation) {
                .make_array => .make_array,
                .make_tuple => .make_tuple,
                .make_set => .make_set,
                .make_dict => .make_dict,
                else => unreachable,
            };
            try chunk.emit(.{ .op = operation, .operand = @intCast(values.len) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .index => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.object)) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.key)) });
            try chunk.emit(.{ .op = .index });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .store_index => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.object)) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.key)) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.value)) });
            try chunk.emit(.{ .op = .store_index });
        },
        .get_property => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.object)) });
            const property = try chunk.addString(value.name);
            try chunk.emit(.{ .op = .get_property, .operand = @intCast(property) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .store_property => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.object)) });
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.value)) });
            const property = try chunk.addString(value.name);
            try chunk.emit(.{ .op = .set_property, .operand = @intCast(property) });
        },
        .call_method => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.receiver)) });
            for (value.arguments) |argument| try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(argument)) });
            try chunk.emit(.{ .op = .call_method, .operand = @intCast(value.function) });
            if (value.returns_receiver) {
                try chunk.emit(.{ .op = .pop });
                try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.receiver)) });
            }
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .call_super => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value.receiver)) });
            for (value.arguments) |argument| try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(argument)) });
            try chunk.emit(.{ .op = .call_super, .operand = @intCast(value.function) });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .try_begin => |target| {
            const index = chunk.code.items.len;
            try chunk.emit(.{ .op = .try_begin, .operand = 0 });
            try pending.append(chunk.allocator, .{ .instruction = index, .target = target });
        },
        .try_end => try chunk.emit(.{ .op = .try_end }),
        .print => |value| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(value)) });
            try chunk.emit(.{ .op = .print });
            try chunk.emit(.{ .op = .none_value });
            if (instruction.result) |result| try chunk.emit(.{ .op = .store_local, .operand = @intCast(@intFromEnum(result)) });
        },
        .jump => |target| {
            try emitPhiEdge(chunk, function, source_block, target);
            const index = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump, .operand = 0 });
            try pending.append(chunk.allocator, .{ .instruction = index, .target = target });
        },
        .branch => |branch| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(branch.condition)) });
            const false_index = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump_if_false, .operand = 0 });
            try emitPhiEdge(chunk, function, source_block, branch.then_block);
            const true_index = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump, .operand = 0 });
            try pending.append(chunk.allocator, .{ .instruction = true_index, .target = branch.then_block });
            const false_edge = chunk.code.items.len;
            chunk.code.items[false_index].operand = @intCast(false_edge);
            try emitPhiEdge(chunk, function, source_block, branch.else_block);
            const false_jump = chunk.code.items.len;
            try chunk.emit(.{ .op = .jump, .operand = 0 });
            try pending.append(chunk.allocator, .{ .instruction = false_jump, .target = branch.else_block });
        },
        .return_value => |value| if (value) |result| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(result)) });
            try chunk.emit(.{ .op = .return_value });
        } else try chunk.emit(.{ .op = .return_value }),
        .raise_value => |value| if (value) |result| {
            try chunk.emit(.{ .op = .load_local, .operand = @intCast(@intFromEnum(result)) });
            try chunk.emit(.{ .op = .raise_value });
        } else try chunk.emit(.{ .op = .raise_value }),
        .suspend_point => |point| try chunk.emit(.{ .op = .suspend_point, .operand = @intCast(point.resume_line) }),
    }
}
