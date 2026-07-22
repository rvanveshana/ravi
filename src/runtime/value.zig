const std = @import("std");

/// The uniform runtime representation used at dynamic boundaries.
pub const Value = union(enum) {
    none,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    array: *ArrayObject,

    pub fn truthy(self: Value) bool {
        return switch (self) {
            .none => false,
            .boolean => |v| v,
            .integer => |v| v != 0,
            .float => |v| v != 0,
            .string => |v| v.len != 0,
            .array => |v| v.items.items.len != 0,
        };
    }
};

pub const ArrayObject = struct {
    items: std.ArrayListUnmanaged(Value) = .empty,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *ArrayObject) void {
        self.items.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};
pub const TupleObject = ArrayObject;
pub const SetObject = ArrayObject;
pub const DictEntry = struct { key: Value, value: Value };
pub const DictObject = struct { items: std.ArrayListUnmanaged(DictEntry) = .empty, allocator: std.mem.Allocator };
pub const Closure = struct {
    function_index: usize,
    captures: []Value,
    allocator: std.mem.Allocator,
    pub fn deinit(self: *Closure) void {
        self.allocator.free(self.captures);
        self.allocator.destroy(self);
    }
};
pub const Heap = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayListUnmanaged(*ArrayObject) = .empty,
    pub fn init(allocator: std.mem.Allocator) Heap {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Heap) void {
        for (self.objects.items) |object| {
            object.items.deinit(object.allocator);
            self.allocator.destroy(object);
        }
        self.objects.deinit(self.allocator);
    }
    pub fn createArray(self: *Heap) !Value {
        const object = try self.allocator.create(ArrayObject);
        object.* = .{ .allocator = self.allocator };
        try self.objects.append(self.allocator, object);
        return .{ .array = object };
    }
    pub fn append(self: *Heap, array: Value, value: Value) !void {
        _ = self;
        try array.array.items.append(array.array.allocator, value);
    }
    pub fn insert(self: *Heap, array: Value, position: usize, value: Value) !void {
        _ = self;
        if (position > array.array.items.items.len) return error.IndexError;
        try array.array.items.insert(array.array.allocator, position, value);
    }
    pub fn pop(self: *Heap, array: Value, position: usize) !Value {
        _ = self;
        if (position >= array.array.items.items.len) return error.IndexError;
        return array.array.items.orderedRemove(position);
    }
    pub fn remove(self: *Heap, array: Value, value: Value) !void {
        _ = self;
        for (array.array.items.items, 0..) |item, i| {
            if (equal(item, value)) {
                _ = array.array.items.orderedRemove(i);
                return;
            }
        }
        return error.IndexError;
    }
    pub fn clear(self: *Heap, array: Value) void {
        _ = self;
        array.array.items.clearRetainingCapacity();
    }
    pub fn contains(self: *Heap, array: Value, value: Value) bool {
        _ = self;
        for (array.array.items.items) |item| if (equal(item, value)) return true;
        return false;
    }
};

pub const DecodeError = std.mem.Allocator.Error || error{ InvalidEscape, UnterminatedString };
pub const OperationError = error{ TypeError, IndexError };
pub fn equal(left: Value, right: Value) bool {
    return switch (left) {
        .none => right == .none,
        .boolean => |v| right == .boolean and v == right.boolean,
        .integer => |v| right == .integer and v == right.integer,
        .float => |v| right == .float and v == right.float,
        .string => |v| right == .string and std.mem.eql(u8, v, right.string),
        .array => |v| right == .array and v == right.array,
    };
}
pub fn index(value: Value, position: usize) OperationError!Value {
    return switch (value) {
        .string => |text| if (position < text.len) .{ .integer = text[position] } else error.IndexError,
        .array => |array| if (position < array.items.items.len) array.items.items[position] else error.IndexError,
        else => error.TypeError,
    };
}
pub fn slice(value: Value, start: usize, end: usize) OperationError!Value {
    return switch (value) {
        .string => |text| if (start <= end and end <= text.len) .{ .string = text[start..end] } else error.IndexError,
        .array => |array| if (start <= end and end <= array.items.items.len) .{ .array = array } else error.IndexError,
        else => error.TypeError,
    };
}

pub fn decodeString(allocator: std.mem.Allocator, token: []const u8) DecodeError![]u8 {
    if (token.len < 2) return error.UnterminatedString;
    const triple = token.len >= 6 and token[0] == token[1] and token[1] == token[2];
    const quote = token[0];
    const start: usize = if (triple) 3 else 1;
    const end_trim: usize = if (triple) 3 else 1;
    if (token.len < start + end_trim or token[token.len - end_trim] != quote) return error.UnterminatedString;
    var result = try allocator.alloc(u8, token.len);
    errdefer allocator.free(result);
    var out: usize = 0;
    var i = start;
    const end = token.len - end_trim;
    while (i < end) : (i += 1) {
        if (token[i] != '\\') {
            result[out] = token[i];
            out += 1;
            continue;
        }
        i += 1;
        if (i >= end) return error.InvalidEscape;
        result[out] = switch (token[i]) {
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            '\\' => '\\',
            '\'' => '\'',
            '"' => '"',
            else => return error.InvalidEscape,
        };
        out += 1;
    }
    return result[0..out];
}
