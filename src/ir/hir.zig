const std = @import("std");
pub const ValueId = enum(u32) { _ };
pub const BlockId = enum(u32) { _ };
pub const Type = enum { none, boolean, integer, float, string, dynamic };
pub fn fromName(name: []const u8) !Type {
    if (std.mem.eql(u8, name, "none")) return .none;
    if (std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "boolean")) return .boolean;
    if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "integer")) return .integer;
    if (std.mem.eql(u8, name, "float")) return .float;
    if (std.mem.eql(u8, name, "str") or std.mem.eql(u8, name, "string")) return .string;
    if (std.mem.eql(u8, name, "dinamika") or std.mem.eql(u8, name, "dynamic")) return .dynamic;
    return error.UnsupportedType;
}
pub const PhiInput = struct { block: BlockId, value: ValueId };
pub const Binary = enum { add, subtract, multiply, divide, modulo, equal, not_equal, less, less_equal, greater, greater_equal, logic_and, logic_or };
pub const Unary = enum { negate, not };
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
        binary: struct { operator: Binary, left: ValueId, right: ValueId },
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
        jump: BlockId,
        branch: struct { condition: ValueId, then_block: BlockId, else_block: BlockId },
        guard: struct { value: ValueId, expected: Type },
        suspend_point: struct { resume_line: usize },
        return_value: ?ValueId,
        raise_value: ?ValueId,
    };
};
pub const Block = struct { first_instruction: usize, instruction_count: usize };
pub const Function = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    instructions: std.ArrayListUnmanaged(Instruction) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    next_value: u32 = 0,
    resumable: bool = false,
    suspension_count: usize = 0,
    parameter_count: usize = 0,
    parameter_types: std.ArrayListUnmanaged(Type) = .empty,
    fixed_count: usize = 0,
    varargs_index: ?usize = null,
    kwargs_index: ?usize = null,
    defaults: [64]?i64 = @splat(null),
    return_type: Type = .dynamic,
    local_count: usize = 0,
    capture_count: usize = 0,
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Function {
        return .{ .allocator = allocator, .name = name };
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
        self.parameter_types.deinit(self.allocator);
    }
    pub fn verify(self: *const Function) !void {
        if (self.blocks.items.len == 0) return error.NoEntryBlock;
        if (self.blocks.items[0].first_instruction != 0) return error.InvalidBlock;
        const definitions = try self.allocator.alloc(bool, self.next_value);
        defer self.allocator.free(definitions);
        @memset(definitions, false);
        const definition_types = try self.allocator.alloc(?Type, self.next_value);
        defer self.allocator.free(definition_types);
        @memset(definition_types, null);
        const covered = try self.allocator.alloc(bool, self.instructions.items.len);
        defer self.allocator.free(covered);
        @memset(covered, false);
        for (self.blocks.items, 0..) |block, block_index| {
            const block_end = std.math.add(usize, block.first_instruction, block.instruction_count) catch return error.InvalidBlock;
            if (block_end > self.instructions.items.len or block.instruction_count == 0) return error.InvalidBlock;
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
                    .parameter => |slot| {
                        if (slot >= self.parameter_count) return error.InvalidParameter;
                        if (self.parameter_types.items.len == self.parameter_count and instruction.result_type != self.parameter_types.items[slot]) return error.InvalidType;
                    },
                    .store_capture => |value| {
                        if (value.slot >= self.capture_count) return error.InvalidCapture;
                        try requireDefined(definitions, value.value);
                    },
                    .binary => |value| {
                        try requireDefined(definitions, value.left);
                        try requireDefined(definitions, value.right);
                        const left_type = definition_types[@intFromEnum(value.left)] orelse return error.UndefinedValue;
                        const right_type = definition_types[@intFromEnum(value.right)] orelse return error.UndefinedValue;
                        const expected: Type = switch (value.operator) {
                            .logic_and, .logic_or => blk: {
                                if (left_type != .boolean or right_type != .boolean) return error.InvalidType;
                                break :blk .boolean;
                            },
                            .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => blk: {
                                if (left_type != right_type and left_type != .dynamic and right_type != .dynamic and !((left_type == .integer or left_type == .float) and (right_type == .integer or right_type == .float))) return error.InvalidType;
                                break :blk .boolean;
                            },
                            else => blk: {
                                if (left_type != right_type or (left_type != .integer and left_type != .float)) return error.InvalidType;
                                break :blk left_type;
                            },
                        };
                        if (instruction.result_type != expected) return error.InvalidType;
                    },
                    .unary => |value| {
                        try requireDefined(definitions, value.operand);
                        try requireType(definition_types, value.operand, if (value.operator == .not) .boolean else .integer);
                        const expected_type: Type = if (value.operator == .not) .boolean else .integer;
                        if (instruction.result_type != expected_type) return error.InvalidType;
                    },
                    .constant_integer => if (instruction.result_type != .integer) return error.InvalidType,
                    .constant_float => if (instruction.result_type != .float) return error.InvalidType,
                    .constant_string => if (instruction.result_type != .string) return error.InvalidType,
                    .constant_boolean => if (instruction.result_type != .boolean) return error.InvalidType,
                    .constant_none => if (instruction.result_type != .none) return error.InvalidType,
                    .store_local => |value| {
                        if (value.slot >= self.local_count) return error.InvalidLocal;
                        try requireDefined(definitions, value.value);
                    },
                    .bind_exception => |slot| if (slot >= self.local_count) return error.InvalidLocal,
                    .phi => |inputs| {
                        if (inputs.len == 0) return error.InvalidPhi;
                        for (inputs) |input| {
                            try requireBlock(self, input.block);
                            try requireValueId(self.next_value, input.value);
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
                    .store_index => |value| {
                        try requireDefined(definitions, value.object);
                        try requireDefined(definitions, value.key);
                        try requireDefined(definitions, value.value);
                    },
                    .print => |value| try requireDefined(definitions, value),
                    .branch => |value| {
                        if (!is_last or @intFromEnum(value.then_block) >= self.blocks.items.len or @intFromEnum(value.else_block) >= self.blocks.items.len) return error.InvalidBlock;
                        try requireDefined(definitions, value.condition);
                        try requireType(definition_types, value.condition, .boolean);
                    },
                    .guard => |value| {
                        try requireDefined(definitions, value.value);
                        if (instruction.result_type != .none and instruction.result_type != value.expected) return error.InvalidType;
                    },
                    .jump => |target| {
                        if (!is_last or @intFromEnum(target) >= self.blocks.items.len) return error.InvalidBlock;
                    },
                    .try_begin => |target| if (@intFromEnum(target) >= self.blocks.items.len) return error.InvalidBlock,
                    .return_value => |value| {
                        if (!is_last) return error.InvalidBlock;
                        if (value) |id| {
                            try requireDefined(definitions, id);
                            const actual = definition_types[@intFromEnum(id)] orelse return error.UndefinedValue;
                            if (self.return_type != .dynamic and actual != self.return_type and actual != .dynamic) return error.InvalidType;
                        }
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
                    definition_types[index] = instruction.result_type;
                }
            }
        }
        for (covered) |is_covered| if (!is_covered) return error.InvalidBlock;
        for (self.instructions.items) |instruction| switch (instruction.operation) {
            .phi => |inputs| {
                const result_type = instruction.result_type;
                for (inputs) |input| {
                    const input_type = definition_types[@intFromEnum(input.value)] orelse return error.UndefinedValue;
                    if (input_type != result_type and input_type != .dynamic and result_type != .dynamic) return error.InvalidType;
                }
            },
            else => {},
        };
    }
    pub fn appendValue(self: *Function, result_type: Type, operation: Instruction.Operation, source_line: usize) !ValueId {
        const result: ValueId = @enumFromInt(self.next_value);
        self.next_value += 1;
        try self.instructions.append(self.allocator, .{ .result = result, .result_type = result_type, .operation = operation, .source_line = source_line });
        return result;
    }
    pub fn appendEffect(self: *Function, operation: Instruction.Operation, source_line: usize) !void {
        try self.instructions.append(self.allocator, .{ .operation = operation, .source_line = source_line });
    }
    pub fn setBlocks(self: *Function, blocks: []const Block) !void {
        try self.blocks.appendSlice(self.allocator, blocks);
    }
    pub fn parameterType(self: *const Function, slot: usize) Type {
        return if (slot < self.parameter_types.items.len) self.parameter_types.items[slot] else .dynamic;
    }
};
fn requireDefined(definitions: []const bool, id: ValueId) !void {
    const index: usize = @intFromEnum(id);
    if (index >= definitions.len or !definitions[index]) return error.UndefinedValue;
}
fn requireType(types: []const ?Type, id: ValueId, expected: Type) !void {
    const actual = types[@intFromEnum(id)] orelse return error.UndefinedValue;
    if (actual != expected and actual != .dynamic) return error.InvalidType;
}
fn requireValueId(value_count: u32, id: ValueId) !void {
    if (@intFromEnum(id) >= value_count) return error.UndefinedValue;
}
fn requireBlock(function: *const Function, block: BlockId) !void {
    if (@intFromEnum(block) >= function.blocks.items.len) return error.InvalidBlock;
}
test "HIR retains types guards and source identity" {
    var function = Function.init(std.testing.allocator, "main");
    defer function.deinit();
    const value = try function.appendValue(.integer, .{ .constant_integer = 42 }, 3);
    try function.appendEffect(.{ .guard = .{ .value = value, .expected = .integer } }, 3);
    try function.appendEffect(.{ .return_value = value }, 3);
    try std.testing.expectEqual(@as(usize, 3), function.instructions.items.len);
    try std.testing.expectEqual(@as(usize, 3), function.instructions.items[0].source_line);
}
test "HIR maps supported annotation names explicitly" {
    try std.testing.expectEqual(Type.integer, try fromName("int"));
    try std.testing.expectEqual(Type.string, try fromName("str"));
    try std.testing.expectEqual(Type.dynamic, try fromName("dinamika"));
    try std.testing.expectError(error.UnsupportedType, fromName("kriya"));
    try std.testing.expectError(error.UnsupportedType, fromName("unknown"));
}
test "HIR records resumable suspension source identity" {
    var function = Function.init(std.testing.allocator, "async_main");
    defer function.deinit();
    function.resumable = true;
    function.suspension_count = 1;
    try function.appendEffect(.{ .suspend_point = .{ .resume_line = 12 } }, 12);
    try std.testing.expect(function.resumable);
    try std.testing.expectEqual(@as(usize, 12), function.instructions.items[0].operation.suspend_point.resume_line);
    try std.testing.expectEqual(@as(usize, 1), function.suspension_count);
}
test "HIR rejects parameters outside the declared signature" {
    var function = Function.init(std.testing.allocator, "identity");
    defer function.deinit();
    function.parameter_count = 1;
    _ = try function.appendValue(.integer, .{ .parameter = 1 }, 1);
    try std.testing.expectError(error.InvalidParameter, function.verify());
}
