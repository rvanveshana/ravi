const std = @import("std");
const hir = @import("ravi_hir");
const verifier = @import("ravi_mir_verify");
pub const ValueId = enum(u32) { _ };
pub const BlockId = enum(u32) { _ };
pub const Type = hir.Type;
pub const Unary = hir.Unary;
pub const Instruction = struct {
    result: ?ValueId = null,
    result_type: Type = .none,
    source_line: usize = 0,
    operation: Operation,
    pub const Operation = union(enum) {
        constant_integer: i64,
        constant_float: f64,
        constant_string: []const u8,
        constant_boolean: bool,
        constant_none,
        unary: struct { operator: Unary, operand: ValueId },
        parameter: usize,
        make_function: usize,
        make_closure: struct { function: usize, captures: []const ValueId },
        make_instance: usize,
        load_local: usize,
        load_capture: usize,
        load_capture_ref: usize,
        store_capture: struct { slot: usize, value: ValueId },
        store_local: struct { slot: usize, value: ValueId },
        bind_exception: usize,
        phi: []const PhiInput,
        binary: struct { operator: hir.Binary, left: ValueId, right: ValueId },
        call: struct { function: usize, arguments: []const ValueId },
        call_value: struct { callee: ValueId, arguments: []const ValueId },
        make_array: []const ValueId,
        make_tuple: []const ValueId,
        make_set: []const ValueId,
        make_dict: []const ValueId,
        index: struct { object: ValueId, key: ValueId },
        store_index: struct { object: ValueId, key: ValueId, value: ValueId },
        get_property: struct { object: ValueId, name: []const u8 },
        store_property: struct { object: ValueId, value: ValueId, name: []const u8 },
        call_method: struct { function: usize, receiver: ValueId, arguments: []const ValueId, returns_receiver: bool = false },
        call_super: struct { function: usize, receiver: ValueId, arguments: []const ValueId },
        try_begin: BlockId,
        try_end,
        print: ValueId,
        guard: struct { value: ValueId, expected: Type },
        suspend_point: struct { resume_line: usize },
        jump: BlockId,
        branch: struct { condition: ValueId, then_block: BlockId, else_block: BlockId },
        return_value: ?ValueId,
        raise_value: ?ValueId,
    };
};
pub const Block = struct { first_instruction: usize, instruction_count: usize };
pub const PhiInput = struct { block: BlockId, value: ValueId };
pub const Function = struct {
    allocator: std.mem.Allocator,
    name: []const u8 = "<function>",
    instructions: std.ArrayListUnmanaged(Instruction) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    value_count: u32 = 0,
    resumable: bool = false,
    suspension_count: usize = 0,
    parameter_count: usize = 0,
    fixed_count: usize = 0,
    varargs_index: ?usize = null,
    kwargs_index: ?usize = null,
    defaults: [64]?i64 = @splat(null),
    local_count: usize = 0,
    capture_count: usize = 0,
    pub fn init(allocator: std.mem.Allocator) Function {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Function) void {
        for (self.instructions.items) |instruction| switch (instruction.operation) {
            .call => |call| self.allocator.free(call.arguments),
            .call_value => |call| self.allocator.free(call.arguments),
            .phi => |inputs| self.allocator.free(inputs),
            .make_array, .make_tuple, .make_set, .make_dict => |values| self.allocator.free(values),
            .make_closure => |closure| self.allocator.free(closure.captures),
            else => {},
        };
        self.instructions.deinit(self.allocator);
        self.blocks.deinit(self.allocator);
    }
    pub fn lower(allocator: std.mem.Allocator, source: *const hir.Function) !Function {
        try source.verify();
        var result = Function.init(allocator);
        errdefer result.deinit();
        for (source.instructions.items) |instruction| {
            const lowered: Instruction.Operation = switch (instruction.operation) {
                .constant_integer => |value| .{ .constant_integer = value },
                .constant_float => |value| .{ .constant_float = value },
                .constant_string => |value| .{ .constant_string = value },
                .constant_boolean => |value| .{ .constant_boolean = value },
                .constant_none => .constant_none,
                .unary => |value| .{ .unary = .{ .operator = value.operator, .operand = mapValue(value.operand) } },
                .parameter => |slot| .{ .parameter = slot },
                .make_function => |index| .{ .make_function = index },
                .make_closure => |closure| .{ .make_closure = .{ .function = closure.function, .captures = try mapArguments(allocator, closure.captures) } },
                .make_instance => |index| .{ .make_instance = index },
                .load_local => |slot| .{ .load_local = slot },
                .load_capture => |slot| .{ .load_capture = slot },
                .load_capture_ref => |slot| .{ .load_capture_ref = slot },
                .store_capture => |value| .{ .store_capture = .{ .slot = value.slot, .value = mapValue(value.value) } },
                .store_local => |value| .{ .store_local = .{ .slot = value.slot, .value = mapValue(value.value) } },
                .bind_exception => |slot| .{ .bind_exception = slot },
                .phi => |inputs| .{ .phi = try mapPhiInputs(allocator, inputs) },
                .binary => |value| .{ .binary = .{ .operator = value.operator, .left = mapValue(value.left), .right = mapValue(value.right) } },
                .call => |value| .{ .call = .{ .function = value.function, .arguments = try mapArguments(allocator, value.arguments) } },
                .call_value => |value| .{ .call_value = .{ .callee = mapValue(value.callee), .arguments = try mapArguments(allocator, value.arguments) } },
                .make_array => |values| .{ .make_array = try mapArguments(allocator, values) },
                .make_tuple => |values| .{ .make_tuple = try mapArguments(allocator, values) },
                .make_set => |values| .{ .make_set = try mapArguments(allocator, values) },
                .make_dict => |values| .{ .make_dict = try mapArguments(allocator, values) },
                .index => |value| .{ .index = .{ .object = mapValue(value.object), .key = mapValue(value.key) } },
                .store_index => |value| .{ .store_index = .{ .object = mapValue(value.object), .key = mapValue(value.key), .value = mapValue(value.value) } },
                .get_property => |value| .{ .get_property = .{ .object = mapValue(value.object), .name = value.name } },
                .store_property => |value| .{ .store_property = .{ .object = mapValue(value.object), .value = mapValue(value.value), .name = value.name } },
                .call_method => |value| .{ .call_method = .{ .function = value.function, .receiver = mapValue(value.receiver), .arguments = try mapArguments(allocator, value.arguments), .returns_receiver = value.returns_receiver } },
                .call_super => |value| .{ .call_super = .{ .function = value.function, .receiver = mapValue(value.receiver), .arguments = try mapArguments(allocator, value.arguments) } },
                .try_begin => |target| .{ .try_begin = @enumFromInt(@intFromEnum(target)) },
                .try_end => .try_end,
                .print => |value| .{ .print = mapValue(value) },
                .jump => |target| .{ .jump = @enumFromInt(@intFromEnum(target)) },
                .branch => |value| .{ .branch = .{ .condition = mapValue(value.condition), .then_block = @enumFromInt(@intFromEnum(value.then_block)), .else_block = @enumFromInt(@intFromEnum(value.else_block)) } },
                .guard => |value| .{ .guard = .{ .value = mapValue(value.value), .expected = value.expected } },
                .suspend_point => |value| .{ .suspend_point = .{ .resume_line = value.resume_line } },
                .return_value => |value| .{ .return_value = if (value) |id| mapValue(id) else null },
                .raise_value => |value| .{ .raise_value = if (value) |id| mapValue(id) else null },
            };
            try result.instructions.append(allocator, .{
                .result = if (instruction.result) |id| mapValue(id) else null,
                .result_type = instruction.result_type,
                .source_line = instruction.source_line,
                .operation = lowered,
            });
        }
        result.value_count = source.next_value;
        result.name = source.name;
        result.resumable = source.resumable;
        result.suspension_count = source.suspension_count;
        result.parameter_count = source.parameter_count;
        result.fixed_count = source.fixed_count;
        result.varargs_index = source.varargs_index;
        result.kwargs_index = source.kwargs_index;
        result.defaults = source.defaults;
        result.local_count = source.local_count;
        result.capture_count = source.capture_count;
        if (source.blocks.items.len == 0) {
            try result.blocks.append(allocator, .{ .first_instruction = 0, .instruction_count = result.instructions.items.len });
        } else for (source.blocks.items) |block| try result.blocks.append(allocator, .{ .first_instruction = block.first_instruction, .instruction_count = block.instruction_count });
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
                    .parameter => |slot| if (slot >= self.parameter_count) return error.InvalidParameter,
                    .load_local => |slot| if (slot >= self.local_count) return error.InvalidLocal,
                    .binary => |value| {
                        try requireDefined(definitions, value.left);
                        try requireDefined(definitions, value.right);
                    },
                    .store_local => |value| {
                        if (value.slot >= self.local_count) return error.InvalidLocal;
                        try requireDefined(definitions, value.value);
                    },
                    .phi => |inputs| {
                        if (inputs.len == 0) return error.InvalidPhi;
                        for (inputs) |input| {
                            try requireBlock(self, input.block);
                            if (@intFromEnum(input.value) >= self.value_count) return error.UndefinedValue;
                        }
                    },
                    .call => |value| for (value.arguments) |argument| try requireDefined(definitions, argument),
                    .call_value => |value| {
                        try requireDefined(definitions, value.callee);
                        for (value.arguments) |argument| try requireDefined(definitions, argument);
                    },
                    .make_array, .make_tuple, .make_set, .make_dict => |values| for (values) |value| try requireDefined(definitions, value),
                    .make_closure => |closure| for (closure.captures) |value| try requireDefined(definitions, value),
                    .index => |value| {
                        try requireDefined(definitions, value.object);
                        try requireDefined(definitions, value.key);
                    },
                    .print => |value| try requireDefined(definitions, value),
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
                    .raise_value => |value| {
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
        try verifier.verifyDominance(self);
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
                        .not_equal, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => null,
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
fn mapArguments(allocator: std.mem.Allocator, arguments: []const hir.ValueId) ![]ValueId {
    const mapped = try allocator.alloc(ValueId, arguments.len);
    for (arguments, 0..) |argument, index| mapped[index] = mapValue(argument);
    return mapped;
}
fn mapPhiInputs(allocator: std.mem.Allocator, inputs: []const hir.PhiInput) ![]PhiInput {
    const mapped = try allocator.alloc(PhiInput, inputs.len);
    for (inputs, 0..) |input, index| mapped[index] = .{ .block = @enumFromInt(@intFromEnum(input.block)), .value = mapValue(input.value) };
    return mapped;
}
fn requireDefined(definitions: []const bool, value: ValueId) !void {
    const index: usize = @intFromEnum(value);
    if (index >= definitions.len or !definitions[index]) return error.UndefinedValue;
}
fn requireBlock(function: *const Function, block: BlockId) !void {
    if (@intFromEnum(block) >= function.blocks.items.len) return error.InvalidBlock;
}
