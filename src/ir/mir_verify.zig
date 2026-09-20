const std = @import("std");
const mir = @import("ravi_mir");

pub fn verifyDominance(function: *const mir.Function) !void {
    const block_count = function.blocks.items.len;
    const instruction_blocks = try function.allocator.alloc(usize, function.instructions.items.len);
    defer function.allocator.free(instruction_blocks);
    @memset(instruction_blocks, 0);
    for (function.blocks.items, 0..) |block, block_index| {
        const end = block.first_instruction + block.instruction_count;
        for (block.first_instruction..end) |instruction| instruction_blocks[instruction] = block_index;
    }
    const definition_blocks = try function.allocator.alloc(?usize, function.value_count);
    defer function.allocator.free(definition_blocks);
    @memset(definition_blocks, null);
    for (function.instructions.items, 0..) |instruction, index| {
        if (instruction.result) |result| definition_blocks[@intFromEnum(result)] = instruction_blocks[index];
    }
    const dominators = try function.allocator.alloc(bool, block_count * block_count);
    defer function.allocator.free(dominators);
    for (0..block_count) |block| {
        for (0..block_count) |candidate| dominators[block * block_count + candidate] = if (block == 0) candidate == 0 else true;
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (1..block_count) |block| {
            var predecessors: [64]usize = undefined;
            var predecessor_count: usize = 0;
            for (function.blocks.items, 0..) |candidate, candidate_index| {
                if (candidate.instruction_count == 0) continue;
                const last = function.instructions.items[candidate.first_instruction + candidate.instruction_count - 1].operation;
                const reaches = switch (last) {
                    .jump => |target| @intFromEnum(target) == block,
                    .branch => |branch| @intFromEnum(branch.then_block) == block or @intFromEnum(branch.else_block) == block,
                    .return_value, .raise_value => false,
                    else => candidate_index + 1 == block and candidate_index + 1 < block_count,
                };
                if (reaches and predecessor_count < predecessors.len) {
                    predecessors[predecessor_count] = candidate_index;
                    predecessor_count += 1;
                }
            }
            if (predecessor_count == 0) continue;
            for (0..block_count) |candidate| {
                var value = true;
                for (predecessors[0..predecessor_count]) |predecessor| value = value and dominators[predecessor * block_count + candidate];
                value = value or candidate == block;
                const slot = block * block_count + candidate;
                if (dominators[slot] != value) {
                    dominators[slot] = value;
                    changed = true;
                }
            }
        }
    }
    for (function.instructions.items, 0..) |instruction, index| {
        const block = instruction_blocks[index];
        const check = struct {
            fn value(definitions: []const ?usize, dom: []const bool, count: usize, blocks: []const usize, current: usize, candidate: mir.ValueId) !void {
                const definition = definitions[@intFromEnum(candidate)] orelse return error.UndefinedValue;
                if (!dom[current * count + definition]) return error.UndefinedValue;
                _ = blocks;
            }
        }.value;
        switch (instruction.operation) {
            .binary => |value| {
                try check(definition_blocks, dominators, block_count, instruction_blocks, block, value.left);
                try check(definition_blocks, dominators, block_count, instruction_blocks, block, value.right);
            },
            .builtin => |value| {
                try check(definition_blocks, dominators, block_count, instruction_blocks, block, value.receiver);
                for (value.arguments) |argument| try check(definition_blocks, dominators, block_count, instruction_blocks, block, argument);
            },
            .call => |value| for (value.arguments) |argument| try check(definition_blocks, dominators, block_count, instruction_blocks, block, argument),
            .store_local => |value| try check(definition_blocks, dominators, block_count, instruction_blocks, block, value.value),
            .guard => |value| try check(definition_blocks, dominators, block_count, instruction_blocks, block, value.value),
            .branch => |value| try check(definition_blocks, dominators, block_count, instruction_blocks, block, value.condition),
            .return_value => |value| if (value) |candidate| try check(definition_blocks, dominators, block_count, instruction_blocks, block, candidate),
            else => {},
        }
    }
}
