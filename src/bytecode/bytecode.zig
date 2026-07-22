const std = @import("std");

pub const OpCode = enum(u8) { halt, constant, make_string, make_function, load_local, store_local, load_capture, load_capture_ref, store_capture, make_closure, make_array, make_tuple, make_set, make_dict, index, slice, store_index, length, type_query, string_lower, string_upper, string_strip, string_find, string_replace, string_split, string_join, append_collection, insert_collection, remove_collection, contains_collection, clear_collection, pop_collection, count_collection, reverse_collection, sort_collection, dict_get, dict_put, dict_remove, dict_contains, dict_keys, dict_values, dict_items, set_union, set_intersection, set_difference, range_condition, dup, guard_integer, guard_float, guard_boolean, guard_string, box_dynamic, unbox_integer, print, pop, add, subtract, multiply, divide, negate, not, equal, not_equal, less, less_equal, greater, greater_equal, logic_and, logic_or, jump_if_false, jump, try_begin, try_end, call, call_value, return_value, raise_value };
pub const Instruction = struct { op: OpCode, operand: i64 = 0 };
pub const FunctionInfo = struct { entry: usize, arity: usize, name: []const u8, capture_count: usize = 0 };
pub const CaptureInfo = struct { function: usize, slot: usize };
pub const SourceLocation = struct { start_offset: usize, end_offset: usize, line: usize, column: usize };
pub const VerifyError = error{ EmptyChunk, InvalidJump, InvalidLocal, StackUnderflow, InvalidInstruction };

pub const Chunk = struct {
    code: std.ArrayListUnmanaged(Instruction) = .empty,
    strings: std.ArrayListUnmanaged([]const u8) = .empty,
    source_map: std.ArrayListUnmanaged(SourceLocation) = .empty,
    functions: std.ArrayListUnmanaged(FunctionInfo) = .empty,
    captures: std.ArrayListUnmanaged(CaptureInfo) = .empty,
    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.source_map.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.captures.deinit(self.allocator);
    }
    pub fn emit(self: *Chunk, instruction: Instruction) !void {
        try self.code.append(self.allocator, instruction);
        try self.source_map.append(self.allocator, .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 });
    }
    pub fn deinitSourceMap(self: *Chunk) void {
        self.source_map.deinit(self.allocator);
    }
    pub fn addFunction(self: *Chunk, function: FunctionInfo) !usize {
        const index = self.functions.items.len;
        try self.functions.append(self.allocator, function);
        return index;
    }
    pub fn addString(self: *Chunk, text: []const u8) !usize {
        const index = self.strings.items.len;
        try self.strings.append(self.allocator, text);
        return index;
    }
    pub fn addCapture(self: *Chunk, capture: CaptureInfo) !void {
        try self.captures.append(self.allocator, capture);
    }
    pub fn verify(self: *const Chunk) VerifyError!void {
        if (self.code.items.len == 0) return error.EmptyChunk;
        var depth: isize = 0;
        for (self.code.items, 0..) |instruction, index| {
            switch (instruction.op) {
                .constant, .make_string, .make_function, .load_local, .load_capture, .load_capture_ref => depth += 1,
                .make_closure, .guard_integer, .guard_float, .guard_boolean, .guard_string, .box_dynamic, .unbox_integer => {},
                .make_array, .make_tuple, .make_set => {
                    if (instruction.operand < 0 or depth < instruction.operand) return error.StackUnderflow;
                    depth -= instruction.operand;
                    depth += 1;
                },
                .make_dict => {
                    if (instruction.operand < 0 or depth < instruction.operand * 2) return error.StackUnderflow;
                    depth -= instruction.operand * 2;
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
                .dict_keys, .dict_values, .dict_items => {
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
                .print => {
                    if (depth < 1) return error.StackUnderflow;
                    depth -= 1;
                },
                .store_local => {
                    if (instruction.operand < 0 or instruction.operand >= 64 or depth < 1) return error.InvalidLocal;
                },
                .store_capture => if (instruction.operand < 0 or instruction.operand >= 64 or depth < 1) return error.InvalidLocal,
                .pop, .negate, .not, .jump_if_false => {
                    if (depth < 1) return error.StackUnderflow;
                    if (instruction.op == .pop or instruction.op == .jump_if_false) depth -= 1;
                },
                .add, .subtract, .multiply, .divide, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .logic_and, .logic_or => {
                    if (depth < 2) return error.StackUnderflow;
                    depth -= 1;
                },
                .call => {
                    if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.functions.items.len))) return error.InvalidInstruction;
                    depth += 1;
                },
                .call_value => {
                    if (instruction.operand < 0 or depth < instruction.operand + 1) return error.StackUnderflow;
                    depth -= instruction.operand;
                },
                .jump => if (instruction.operand < 0 or instruction.operand >= @as(i64, @intCast(self.code.items.len))) return error.InvalidJump,
                .try_begin, .try_end => {},
                .return_value, .halt => {},
                .raise_value => if (depth < 1) return error.StackUnderflow,
            }
            _ = index;
        }
    }
};
