const std = @import("std");
const packed_codec = @import("ravi_packed_bytecode");
const verifier = @import("ravi_bytecode_verifier");
pub const opcode_spec = @import("ravi_opcode_spec");

pub const OpCode = packed_codec.OpCode;
pub const Instruction = packed_codec.Instruction;
pub const PackedInstruction = packed_codec.PackedInstruction;
pub const encodePackedCode = packed_codec.encodePackedCode;
pub const decodePackedCode = packed_codec.decodePackedCode;
pub const VerifyError = verifier.VerifyError;

pub const FunctionInfo = struct {
    entry: usize,
    arity: usize,
    fixed_count: usize = 0,
    varargs_index: ?usize = null,
    kwargs_index: ?usize = null,
    name: []const u8,
    defaults: [64]?i64 = @splat(null),
    capture_count: usize = 0,
    resumable: bool = false,
    suspension_count: usize = 0,
};

pub const ClassInfo = struct {
    name: []const u8,
    base: ?usize = null,
    is_exception: bool = false,

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
pub const RootMetadata = struct { stack_slots: usize = 0, local_slots: usize = 0, capture_slots: usize = 0 };

pub const Chunk = struct {
    code: std.ArrayListUnmanaged(Instruction) = .empty,
    strings: std.ArrayListUnmanaged([]const u8) = .empty,
    formats: std.ArrayListUnmanaged(struct { template: []const u8, arg_count: usize }) = .empty,
    floats: std.ArrayListUnmanaged(f64) = .empty,
    source_map: std.ArrayListUnmanaged(SourceLocation) = .empty,
    root_map: std.ArrayListUnmanaged(RootMetadata) = .empty,
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
        for (self.strings.items) |text| self.allocator.free(text);
        self.strings.deinit(self.allocator);
        self.formats.deinit(self.allocator);
        self.floats.deinit(self.allocator);
        self.source_map.deinit(self.allocator);
        self.root_map.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.classes.deinit(self.allocator);
        self.methods.deinit(self.allocator);
        self.captures.deinit(self.allocator);
    }

    pub fn emit(self: *Chunk, instruction: Instruction) !void {
        try self.code.append(self.allocator, instruction);
        errdefer _ = self.code.pop();
        try self.source_map.append(self.allocator, self.current_location);
        errdefer _ = self.source_map.pop();
        try self.root_map.append(self.allocator, .{});
    }

    pub fn setRootMetadata(self: *Chunk, first: usize, metadata: RootMetadata) !void {
        if (first > self.root_map.items.len) return error.InvalidMetadata;
        for (self.root_map.items[first..]) |*entry| entry.* = metadata;
    }

    pub fn encodePacked(self: *const Chunk, allocator: std.mem.Allocator) ![]u8 {
        return encodePackedCode(allocator, self.code.items);
    }

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
        const owned = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned);
        try self.strings.append(self.allocator, owned);
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
        return verifier.verify(self);
    }
};

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
    const classes = [_]ClassInfo{ .{ .name = "Animal" }, .{ .name = "Dog", .base = 0 }, .{ .name = "GuideDog", .base = 1 } };
    try std.testing.expect(ClassInfo.inheritsFrom(&classes, 2, 0));
    try std.testing.expect(ClassInfo.inheritsFrom(&classes, 1, 1));
    try std.testing.expect(!ClassInfo.inheritsFrom(&classes, 0, 2));
    try std.testing.expect(!ClassInfo.inheritsFrom(&classes, 99, 0));
}

test "method lookup prefers override then walks single base chain" {
    const classes = [_]ClassInfo{ .{ .name = "Base" }, .{ .name = "Child", .base = 0 } };
    const methods = [_]MethodInfo{ .{ .class_index = 0, .name = "read", .function_index = 4 }, .{ .class_index = 1, .name = "read", .function_index = 9 }, .{ .class_index = 0, .name = "only_base", .function_index = 5 } };
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
