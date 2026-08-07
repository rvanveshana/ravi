const std = @import("std");
const hir = @import("ravi_hir");

pub const ValueId = enum(u32) { _ };
pub const BlockId = enum(u32) { _ };
pub const Type = hir.Type;

pub const Instruction = struct {
    result: ?ValueId = null,
    result_type: Type = .none,
    source_line: usize = 0,
    operation: Operation,

    pub const Operation = union(enum) {
        constant_integer: i64,
        binary: struct { operator: hir.Binary, left: ValueId, right: ValueId },
        guard: struct { value: ValueId, expected: Type },
        suspend_point: struct { resume_line: usize },
        jump: BlockId,
        branch: struct { condition: ValueId, then_block: BlockId, else_block: BlockId },
        return_value: ?ValueId,
    };
};

pub const Block = struct { first_instruction: usize, instruction_count: usize };

pub const Function = struct {
    allocator: std.mem.Allocator,
    instructions: std.ArrayListUnmanaged(Instruction) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    value_count: u32 = 0,
    resumable: bool = false,
    suspension_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Function {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Function) void {
        self.instructions.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
    }

    pub fn lower(allocator: std.mem.Allocator, source: *const hir.Function) !Function {
        var result = Function.init(allocator);
        errdefer result.deinit();
        for (source.instructions.items) |instruction| {
            const lowered: Instruction.Operation = switch (instruction.operation) {
                .constant_integer => |value| .{ .constant_integer = value },
                .binary => |value| .{ .binary = .{ .operator = value.operator, .left = mapValue(value.left), .right = mapValue(value.right) } },
                .guard => |value| .{ .guard = .{ .value = mapValue(value.value), .expected = value.expected } },
                .suspend_point => |value| .{ .suspend_point = .{ .resume_line = value.resume_line } },
                .return_value => |value| .{ .return_value = if (value) |id| mapValue(id) else null },
            };
            try result.instructions.append(allocator, .{
                .result = if (instruction.result) |id| mapValue(id) else null,
                .result_type = instruction.result_type,
                .source_line = instruction.source_line,
                .operation = lowered,
            });
        }
        result.value_count = source.next_value;
        result.resumable = source.resumable;
        result.suspension_count = source.suspension_count;
        try result.blocks.append(allocator, .{ .first_instruction = 0, .instruction_count = result.instructions.items.len });
        try result.verify();
        return result;
    }

    pub fn verify(self: *const Function) !void {
        if (self.blocks.items.len == 0) return error.NoEntryBlock;
        var suspension_count: usize = 0;
        for (self.instructions.items) |instruction| {
            if (instruction.operation == .suspend_point) suspension_count += 1;
        }
        if (suspension_count != self.suspension_count or (self.resumable and suspension_count == 0) or (!self.resumable and suspension_count != 0)) return error.InvalidResumableMetadata;
        // The first block is the function entry; allowing a non-zero offset
        // would leave instructions outside the CFG and make source/debug
        // identities ambiguous.
        if (self.blocks.items[0].first_instruction != 0) return error.InvalidBlock;
        const definitions = try self.allocator.alloc(bool, self.value_count);
        defer self.allocator.free(definitions);
        @memset(definitions, false);
        const covered = try self.allocator.alloc(bool, self.instructions.items.len);
        defer self.allocator.free(covered);
        @memset(covered, false);
        for (self.blocks.items, 0..) |block, block_index| {
            const block_end = std.math.add(usize, block.first_instruction, block.instruction_count) catch return error.InvalidBlock;
            if (block_end > self.instructions.items.len) return error.InvalidBlock;
            for (self.blocks.items[0..block_index]) |previous| {
                const previous_end = std.math.add(usize, previous.first_instruction, previous.instruction_count) catch return error.InvalidBlock;
                if (block.first_instruction < previous_end and previous.first_instruction < block_end) return error.InvalidBlock;
            }
            for (block.first_instruction..block_end) |instruction_index| {
                if (covered[instruction_index]) return error.InvalidBlock;
                covered[instruction_index] = true;
                const instruction = self.instructions.items[instruction_index];
                const is_last = instruction_index + 1 == block_end;
                switch (instruction.operation) {
                    .binary => |value| {
                        try requireDefined(definitions, value.left);
                        try requireDefined(definitions, value.right);
                    },
                    .guard => |value| try requireDefined(definitions, value.value),
                    .branch => |value| {
                        if (!is_last) return error.InvalidBlock;
                        try requireDefined(definitions, value.condition);
                        try requireBlock(self, value.then_block);
                        try requireBlock(self, value.else_block);
                    },
                    .jump => |target| {
                        if (!is_last) return error.InvalidBlock;
                        try requireBlock(self, target);
                    },
                    .return_value => |value| {
                        if (!is_last) return error.InvalidBlock;
                        if (value) |id| try requireDefined(definitions, id);
                    },
                    else => {},
                }
                if (instruction.result) |id| {
                    const index: usize = @intFromEnum(id);
                    if (index >= definitions.len or definitions[index]) return error.InvalidDefinition;
                    definitions[index] = true;
                }
            }
        }
        for (covered) |is_covered| if (!is_covered) return error.InvalidBlock;
    }

    pub fn foldConstants(self: *Function) !usize {
        const constants = try self.allocator.alloc(?i64, self.value_count);
        defer self.allocator.free(constants);
        @memset(constants, null);
        var changed: usize = 0;
        for (self.instructions.items) |*instruction| {
            const result = instruction.result orelse continue;
            const result_index: usize = @intFromEnum(result);
            if (result_index >= constants.len) return error.InvalidDefinition;
            switch (instruction.operation) {
                .constant_integer => |value| constants[result_index] = value,
                .binary => |binary| {
                    const left_index = @intFromEnum(binary.left);
                    const right_index = @intFromEnum(binary.right);
                    if (left_index >= constants.len or right_index >= constants.len) return error.UndefinedValue;
                    const left = constants[left_index] orelse continue;
                    const right = constants[right_index] orelse continue;
                    const folded: ?i64 = switch (binary.operator) {
                        .add => left +% right,
                        .subtract => left -% right,
                        .multiply => left *% right,
                        .divide => if (right == 0 or (left == std.math.minInt(i64) and right == -1)) null else @divTrunc(left, right),
                        .modulo => if (right == 0) null else @mod(left, right),
                        .equal => @intFromBool(left == right),
                        .less => @intFromBool(left < right),
                    };
                    if (folded) |value| {
                        instruction.operation = .{ .constant_integer = value };
                        constants[result_index] = value;
                        changed += 1;
                    }
                },
                else => {},
            }
        }
        try self.verify();
        return changed;
    }
};

fn mapValue(value: hir.ValueId) ValueId {
    return @enumFromInt(@intFromEnum(value));
}
fn requireDefined(definitions: []const bool, value: ValueId) !void {
    const index: usize = @intFromEnum(value);
    if (index >= definitions.len or !definitions[index]) return error.UndefinedValue;
}
fn requireBlock(function: *const Function, block: BlockId) !void {
    if (@intFromEnum(block) >= function.blocks.items.len) return error.InvalidBlock;
}

test "HIR lowers to verified MIR with stable source lines" {
    var source = hir.Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const left = try source.appendValue(.integer, .{ .constant_integer = 20 }, 1);
    const right = try source.appendValue(.integer, .{ .constant_integer = 22 }, 1);
    const sum = try source.appendValue(.integer, .{ .binary = .{ .operator = .add, .left = left, .right = right } }, 1);
    try source.appendEffect(.{ .return_value = sum }, 1);
    var function = try Function.lower(std.testing.allocator, &source);
    defer function.deinit();
    try std.testing.expectEqual(@as(usize, 1), function.blocks.items.len);
    try std.testing.expectEqual(@as(usize, 1), function.instructions.items[2].source_line);
    try std.testing.expectEqual(@as(usize, 1), try function.foldConstants());
    try std.testing.expectEqual(@as(i64, 42), function.instructions.items[2].operation.constant_integer);
}

test "constant folding preserves trapping division" {
    var source = hir.Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const numerator = try source.appendValue(.integer, .{ .constant_integer = 1 }, 1);
    const zero = try source.appendValue(.integer, .{ .constant_integer = 0 }, 1);
    _ = try source.appendValue(.integer, .{ .binary = .{ .operator = .divide, .left = numerator, .right = zero } }, 1);
    var function = try Function.lower(std.testing.allocator, &source);
    defer function.deinit();
    try std.testing.expectEqual(@as(usize, 0), try function.foldConstants());
    try std.testing.expect(function.instructions.items[2].operation == .binary);
}

test "constant folding handles modulo and preserves zero divisor" {
    var source = hir.Function.init(std.testing.allocator, "main");
    defer source.deinit();
    const left = try source.appendValue(.integer, .{ .constant_integer = 17 }, 1);
    const right = try source.appendValue(.integer, .{ .constant_integer = 5 }, 1);
    _ = try source.appendValue(.integer, .{ .binary = .{ .operator = .modulo, .left = left, .right = right } }, 1);
    var function = try Function.lower(std.testing.allocator, &source);
    defer function.deinit();
    try std.testing.expectEqual(@as(usize, 1), try function.foldConstants());
    try std.testing.expectEqual(@as(i64, 2), function.instructions.items[2].operation.constant_integer);
}

test "MIR preserves resumable machine metadata" {
    var source = hir.Function.init(std.testing.allocator, "async_main");
    defer source.deinit();
    source.resumable = true;
    source.suspension_count = 1;
    try source.appendEffect(.{ .suspend_point = .{ .resume_line = 8 } }, 8);
    var lowered = try Function.lower(std.testing.allocator, &source);
    defer lowered.deinit();
    try std.testing.expect(lowered.resumable);
    try std.testing.expectEqual(@as(usize, 1), lowered.suspension_count);
    try std.testing.expectEqual(@as(usize, 8), lowered.instructions.items[0].operation.suspend_point.resume_line);
}

test "MIR constant folding rejects malformed value identifiers" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();
    function.value_count = 1;
    try function.instructions.append(std.testing.allocator, .{
        .result = @enumFromInt(0),
        .result_type = .integer,
        .source_line = 1,
        .operation = .{ .binary = .{ .operator = .add, .left = @enumFromInt(9), .right = @enumFromInt(0) } },
    });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try std.testing.expectError(error.UndefinedValue, function.foldConstants());
}

test "MIR verifier rejects overlapping and overflowing blocks" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
    function.blocks.items[1] = .{ .first_instruction = std.math.maxInt(usize), .instruction_count = 1 };
    try std.testing.expectError(error.InvalidBlock, function.verify());
}

test "MIR verifier rejects uncovered instructions" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.instructions.append(std.testing.allocator, .{ .source_line = 2, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 1 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
}

test "MIR verifier requires the first block to be the entry offset" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 1, .instruction_count = 0 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
}

test "MIR verifier requires control-flow terminators at block end" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .jump = @enumFromInt(0) } });
    try function.instructions.append(std.testing.allocator, .{ .source_line = 1, .operation = .{ .return_value = null } });
    try function.blocks.append(std.testing.allocator, .{ .first_instruction = 0, .instruction_count = 2 });
    try std.testing.expectError(error.InvalidBlock, function.verify());
}
