const std = @import("std");

pub const OpCode = enum(u8) { halt, suspend_point, constant, make_string, make_function, make_instance, get_property, set_property, load_local, store_local, load_capture, load_capture_ref, store_capture, make_closure, make_array, make_tuple, make_set, make_dict, index, slice, store_index, length, iterable, type_query, string_lower, string_upper, string_strip, string_find, string_replace, string_split, string_join, append_collection, insert_collection, remove_collection, contains_collection, clear_collection, pop_collection, count_collection, reverse_collection, sort_collection, dict_get, dict_put, dict_remove, dict_contains, dict_keys, dict_values, dict_items, set_union, set_intersection, set_difference, range_condition, range_step, dup, guard_integer, guard_float, guard_boolean, guard_string, box_dynamic, unbox_integer, print, pop, add, subtract, multiply, divide, modulo, negate, not, equal, not_equal, less, less_equal, greater, greater_equal, logic_and, logic_or, jump_if_false, jump, try_begin, try_end, call, call_method, call_super, call_value, return_value, raise_value, true_value, false_value, make_float, make_format };
pub const Instruction = struct { op: OpCode, operand: i64 = 0 };

/// Compact on-disk/cache representation: one opcode byte plus a signed
/// 24-bit operand. The live VM keeps `Instruction` for compatibility while
/// bytecode artifacts can use this format to reduce operand bandwidth.
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

test "packed instructions round-trip signed operands" {
    const encoded = try PackedInstruction.encode(.{ .op = .jump, .operand = -42 });
    const decoded = try encoded.decode();
    try std.testing.expectEqual(OpCode.jump, decoded.op);
    try std.testing.expectEqual(@as(i64, -42), decoded.operand);
    try std.testing.expectError(error.OperandOutOfRange, PackedInstruction.encode(.{ .op = .jump, .operand = 8_388_608 }));
}

test "packed code serializer round-trips instruction streams" {
    const source = [_]Instruction{ .{ .op = .constant, .operand = 42 }, .{ .op = .jump, .operand = -3 }, .{ .op = .return_value } };
    const bytes = try encodePackedCode(std.testing.allocator, &source);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 12), bytes.len);
    const decoded = try decodePackedCode(std.testing.allocator, bytes);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualSlices(Instruction, &source, decoded);
    try std.testing.expectError(error.InvalidInstruction, decodePackedCode(std.testing.allocator, bytes[0..3]));
}

test "chunk exposes packed release boundary without losing metadata" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .constant, .operand = 7 });
    try chunk.emit(.{ .op = .return_value });
    const packed_bytes = try chunk.encodePacked(std.testing.allocator);
    defer std.testing.allocator.free(packed_bytes);
    try std.testing.expectEqual(@as(usize, 8), packed_bytes.len);
    try chunk.loadPacked(packed_bytes);
    try std.testing.expectEqual(@as(usize, 2), chunk.code.items.len);
    try std.testing.expectEqual(@as(usize, 2), chunk.source_map.items.len);
}

test "class metadata resolves single-inheritance ancestry safely" {
    const classes = [_]ClassInfo{
        .{ .name = "Animal" },
        .{ .name = "Dog", .base = 0 },
        .{ .name = "GuideDog", .base = 1 },
    };
    try std.testing.expect(ClassInfo.inheritsFrom(&classes, 2, 0));
    try std.testing.expect(ClassInfo.inheritsFrom(&classes, 1, 1));
    try std.testing.expect(!ClassInfo.inheritsFrom(&classes, 0, 2));
    try std.testing.expect(!ClassInfo.inheritsFrom(&classes, 99, 0));
}

test "method lookup prefers override then walks single base chain" {
    const classes = [_]ClassInfo{ .{ .name = "Base" }, .{ .name = "Child", .base = 0 } };
    const methods = [_]MethodInfo{
        .{ .class_index = 0, .name = "read", .function_index = 4 },
        .{ .class_index = 1, .name = "read", .function_index = 9 },
        .{ .class_index = 0, .name = "only_base", .function_index = 5 },
    };
    try std.testing.expectEqual(@as(?usize, 9), lookupMethod(&classes, &methods, 1, "read"));
    try std.testing.expectEqual(@as(?usize, 5), lookupMethod(&classes, &methods, 1, "only_base"));
    try std.testing.expect(lookupMethod(&classes, &methods, 1, "missing") == null);
}

test "protected access follows the single-inheritance chain" {
    const classes = [_]ClassInfo{ .{ .name = "Base" }, .{ .name = "Child", .base = 0 }, .{ .name = "Other" } };
    try std.testing.expect(canAccessProtected(&classes, 0, 0));
    try std.testing.expect(canAccessProtected(&classes, 0, 1));
    try std.testing.expect(!canAccessProtected(&classes, 0, 2));
    try std.testing.expect(!canAccessProtected(&classes, 0, null));
}
pub const FunctionInfo = struct {
    entry: usize,
    arity: usize,
    name: []const u8,
    defaults: [64]?i64 = @splat(null),
    capture_count: usize = 0,
    /// True when the function contains a suspension point and requires a
    /// resumable execution frame once async lowering is enabled.
    resumable: bool = false,
    suspension_count: usize = 0,
};
pub const ClassInfo = struct {
    name: []const u8,
    base: ?usize = null,

    pub fn inheritsFrom(classes: []const ClassInfo, child: usize, ancestor: usize) bool {
        if (child >= classes.len or ancestor >= classes.len) return false;
        var current = child;
        var steps: usize = 0;
        while (steps <= classes.len) : (steps += 1) {
            if (current == ancestor) return true;
            current = classes[current].base orelse return false;
            if (current >= classes.len) return false;
        }
        return false;
    }
};
pub const MethodInfo = struct { class_index: usize, name: []const u8, function_index: usize, visibility: u8 = 0 };

pub fn lookupMethod(classes: []const ClassInfo, methods: []const MethodInfo, class_index: usize, name: []const u8) ?usize {
    if (class_index >= classes.len) return null;
    var current = class_index;
    var steps: usize = 0;
    while (steps <= classes.len) : (steps += 1) {
        var index = methods.len;
        while (index > 0) {
            index -= 1;
            const method = methods[index];
            if (method.class_index == current and std.mem.eql(u8, method.name, name)) return method.function_index;
        }
        current = classes[current].base orelse return null;
        if (current >= classes.len) return null;
    }
    return null;
}

pub fn canAccessProtected(classes: []const ClassInfo, declaring_class: usize, caller_class: ?usize) bool {
    const caller = caller_class orelse return false;
    return ClassInfo.inheritsFrom(classes, caller, declaring_class);
}
pub const CaptureInfo = struct { function: usize, slot: usize };
pub const SourceLocation = struct { start_offset: usize, end_offset: usize, line: usize, column: usize };
pub const VerifyError = error{ EmptyChunk, InvalidJump, InvalidLocal, StackUnderflow, InvalidInstruction };

pub const Chunk = struct {
    code: std.ArrayListUnmanaged(Instruction) = .empty,
    strings: std.ArrayListUnmanaged([]const u8) = .empty,
    formats: std.ArrayListUnmanaged(struct { template: []const u8, arg_count: usize }) = .empty,
    floats: std.ArrayListUnmanaged(f64) = .empty,
    source_map: std.ArrayListUnmanaged(SourceLocation) = .empty,
    functions: std.ArrayListUnmanaged(FunctionInfo) = .empty,
    classes: std.ArrayListUnmanaged(ClassInfo) = .empty,
    methods: std.ArrayListUnmanaged(MethodInfo) = .empty,
    captures: std.ArrayListUnmanaged(CaptureInfo) = .empty,
    allocator: std.mem.Allocator,
    current_location: SourceLocation = .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 },
    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.formats.deinit(self.allocator);
        self.floats.deinit(self.allocator);
        self.source_map.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.classes.deinit(self.allocator);
        self.methods.deinit(self.allocator);
        self.captures.deinit(self.allocator);
    }
    pub fn emit(self: *Chunk, instruction: Instruction) !void {
        try self.code.append(self.allocator, instruction);
        errdefer _ = self.code.pop();
        try self.source_map.append(self.allocator, self.current_location);
    }

    /// Return the compact representation used by cached/release artifacts.
    /// Source maps and metadata intentionally remain on the Chunk so debugger
    /// builds can continue to execute the full instruction stream.
    pub fn encodePacked(self: *const Chunk, allocator: std.mem.Allocator) ![]u8 {
        return encodePackedCode(allocator, self.code.items);
    }

    /// Replace only the executable instruction stream from a packed artifact.
    /// A source map is not fabricated: callers must provide one (or keep this
    /// chunk in release/no-debug mode) before calling `verify`.
    pub fn loadPacked(self: *Chunk, bytes: []const u8) !void {
        const decoded = try decodePackedCode(self.allocator, bytes);
        defer self.allocator.free(decoded);
        self.code.clearRetainingCapacity();
        try self.code.appendSlice(self.allocator, decoded);
    }
    pub fn setSourceLocation(self: *Chunk, location: SourceLocation) void {
        self.current_location = location;
    }
    pub fn deinitSourceMap(self: *Chunk) void {
        self.source_map.deinit(self.allocator);
    }
    pub fn addFunction(self: *Chunk, function: FunctionInfo) !usize {
        const index = self.functions.items.len;
        try self.functions.append(self.allocator, function);
        return index;
    }
    pub fn addClass(self: *Chunk, class: ClassInfo) !usize {
        const index = self.classes.items.len;
        try self.classes.append(self.allocator, class);
        return index;
    }
    pub fn addString(self: *Chunk, text: []const u8) !usize {
        for (self.strings.items, 0..) |existing, index| if (std.mem.eql(u8, existing, text)) return index;
        const index = self.strings.items.len;
        try self.strings.append(self.allocator, text);
        return index;
    }

    pub fn addFormat(self: *Chunk, template: []const u8, arg_count: usize) !usize {
        const index = self.formats.items.len;
        try self.formats.append(self.allocator, .{ .template = template, .arg_count = arg_count });
        return index;
    }
    pub fn addFloat(self: *Chunk, value: f64) !usize {
        for (self.floats.items, 0..) |existing, index| if (existing == value) return index;
        const index = self.floats.items.len;
        try self.floats.append(self.allocator, value);
        return index;
    }
    pub fn addCapture(self: *Chunk, capture: CaptureInfo) !void {
        try self.captures.append(self.allocator, capture);
    }
    pub fn verify(self: *const Chunk) VerifyError!void {
        if (self.code.items.len == 0) return error.EmptyChunk;
        if (self.source_map.items.len != self.code.items.len) return error.InvalidInstruction;
        for (self.functions.items) |function| {
            if (function.entry == 0 or function.entry >= self.code.items.len) return error.InvalidInstruction;
            if ((!function.resumable and function.suspension_count != 0) or (function.resumable and function.suspension_count == 0)) return error.InvalidInstruction;
        }
        for (self.captures.items) |capture| if (capture.function >= self.functions.items.len) return error.InvalidInstruction;
        var depth: isize = 0;
        for (self.code.items, 0..) |instruction, index| {
            switch (instruction.op) {
                .constant, .make_string, .make_function, .make_instance, .load_local, .load_capture, .load_capture_ref, .true_value, .false_value, .make_float => depth += 1,
                .make_format => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.formats.items.len))) return error.InvalidInstruction;
                    const argument_count = self.formats.items[@intCast(instruction.operand)].arg_count;
                    if (argument_count > std.math.maxInt(isize)) return error.InvalidInstruction;
                    if (depth < @as(isize, @intCast(argument_count))) return error.StackUnderflow;
                    depth -= @as(isize, @intCast(argument_count));
                    depth += 1;
                },
                .get_property, .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer => {},
                .suspend_point => if (instruction.operand < 0) return error.InvalidInstruction,
                .make_closure => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                    const captures: isize = @intCast(self.functions.items[@intCast(instruction.operand)].capture_count);
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
                    if (instruction.op == .length) {} else depth += 1;
                },
                .string_lower, .string_upper, .string_strip => {
                    if (depth < 1) return error.StackUnderflow;
                },
                .type_query => if (depth < 1) return error.StackUnderflow,
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
                    if (instruction.op == .contains_collection) depth -= 1 else depth -= 1;
                },
                .insert_collection => {
                    if (depth < 3) return error.StackUnderflow;
                    depth -= 3;
                },
                .remove_collection => {
                    if (depth < 2) return error.StackUnderflow;
                    depth -= 2;
                },
                .clear_collection => {
                    if (depth < 1) return error.StackUnderflow;
                    depth -= 1;
                },
                .pop_collection => {
                    if (depth < 1) return error.StackUnderflow;
                },
                .reverse_collection, .sort_collection => {
                    if (depth < 1) return error.StackUnderflow;
                    depth -= 1;
                },
                .dict_get, .dict_contains => {
                    if (depth < 2) return error.StackUnderflow;
                    // handle + key becomes one value
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
                .dict_keys, .dict_values, .dict_items, .iterable => {
                    if (depth < 1) return error.StackUnderflow;
                },
                .set_union, .set_intersection, .set_difference => {
                    if (depth < 2) return error.StackUnderflow;
                    depth -= 1;
                },
                .range_condition => {
                    if (depth < 3) return error.StackUnderflow;
                    depth -= 2;
                },
                .range_step => {
                    if (instruction.operand < 0 or depth < 0) return error.InvalidLocal;
                    if (instruction.operand > std.math.maxInt(isize)) return error.InvalidLocal;
                },
                .print => {
                    if (depth < 1) return error.StackUnderflow;
                    depth -= 1;
                },
                .store_local => {
                    if (instruction.operand < 0 or depth < 1) return error.InvalidLocal;
                },
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
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                    depth += 1;
                },
                .call_method, .call_super => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                    const arity: isize = @intCast(self.functions.items[@intCast(instruction.operand)].arity);
                    if (depth < arity + 1) return error.StackUnderflow;
                    depth -= arity;
                },
                .call_value => {
                    if (instruction.operand < 0 or instruction.operand >= std.math.maxInt(isize)) return error.InvalidInstruction;
                    if (depth < instruction.operand + 1) return error.StackUnderflow;
                    depth -= instruction.operand;
                },
                .jump => if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.code.items.len))) return error.InvalidJump,
                .try_begin, .try_end => {},
                .return_value, .halt => {},
                .raise_value => if (depth < 1) return error.StackUnderflow,
            }
            _ = index;
        }
        try self.verifyControlFlow();
    }

    fn verifyControlFlow(self: *const Chunk) VerifyError!void {
        const depths = self.allocator.alloc(?isize, self.code.items.len) catch return error.InvalidInstruction;
        defer self.allocator.free(depths);
        @memset(depths, null);
        var work: std.ArrayListUnmanaged(struct { instruction: usize, depth: isize }) = .empty;
        defer work.deinit(self.allocator);
        work.append(self.allocator, .{ .instruction = 0, .depth = 0 }) catch return error.InvalidInstruction;
        for (self.functions.items) |function| {
            if (function.entry >= self.code.items.len) return error.InvalidInstruction;
            work.append(self.allocator, .{ .instruction = function.entry, .depth = 0 }) catch return error.InvalidInstruction;
        }

        while (work.pop()) |state| {
            if (depths[state.instruction]) |known| {
                if (known != state.depth and self.code.items[state.instruction].op != .return_value and self.code.items[state.instruction].op != .halt) return error.InvalidInstruction;
                continue;
            }
            depths[state.instruction] = state.depth;
            const instruction = self.code.items[state.instruction];
            const next_depth = try self.stackAfter(instruction, state.depth);
            switch (instruction.op) {
                .jump => try appendState(self, &work, instruction.operand, next_depth),
                .jump_if_false => {
                    try appendState(self, &work, instruction.operand, next_depth);
                    if (state.instruction + 1 < self.code.items.len) work.append(self.allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.InvalidInstruction;
                },
                .try_begin => {
                    try appendState(self, &work, instruction.operand, next_depth);
                    if (state.instruction + 1 < self.code.items.len) work.append(self.allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.InvalidInstruction;
                },
                .return_value, .halt, .raise_value, .suspend_point => {},
                else => if (state.instruction + 1 < self.code.items.len) work.append(self.allocator, .{ .instruction = state.instruction + 1, .depth = next_depth }) catch return error.InvalidInstruction,
            }
        }
    }

    fn appendState(self: *const Chunk, work: anytype, operand: i64, depth: isize) VerifyError!void {
        if (operand < 0 or operand >= @as(i64, @intCast(self.code.items.len))) return error.InvalidJump;
        work.append(self.allocator, .{ .instruction = @as(usize, @intCast(operand)), .depth = depth }) catch return error.InvalidInstruction;
    }

    fn stackAfter(self: *const Chunk, instruction: Instruction, depth: isize) VerifyError!isize {
        var required: isize = 0;
        var delta: isize = 0;
        switch (instruction.op) {
            .constant, .true_value, .false_value => delta = 1,
            .make_format => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.formats.items.len))) return error.InvalidInstruction;
                const argument_count = self.formats.items[@intCast(instruction.operand)].arg_count;
                if (argument_count > std.math.maxInt(isize)) return error.InvalidInstruction;
                required = @intCast(argument_count);
                delta = 1 - required;
            },
            .make_float => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.floats.items.len))) return error.InvalidInstruction;
                delta = 1;
            },
            .make_string => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.strings.items.len))) return error.InvalidInstruction;
                delta = 1;
            },
            .make_function => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                delta = 1;
            },
            .make_instance => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.classes.items.len))) return error.InvalidInstruction;
                delta = 1;
            },
            .load_local => {
                if (instruction.operand < 0) return error.InvalidLocal;
                delta = 1;
            },
            .load_capture, .load_capture_ref => {
                if (instruction.operand < 0) return error.InvalidLocal;
                delta = 1;
            },
            .store_local, .store_capture, .get_property, .length, .iterable, .type_query, .string_lower, .string_upper, .string_strip, .pop_collection, .dict_keys, .dict_values, .dict_items, .negate, .not, .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer => required = 1,
            .try_begin, .try_end, .jump, .halt, .return_value, .suspend_point, .range_step => {},
            .make_closure => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                required = @intCast(self.functions.items[@intCast(instruction.operand)].capture_count);
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
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                required = @intCast(self.functions.items[@intCast(instruction.operand)].arity);
                delta = 1 - required;
            },
            .call_method, .call_super => {
                if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                required = @as(isize, @intCast(self.functions.items[@intCast(instruction.operand)].arity)) + 1;
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
};
