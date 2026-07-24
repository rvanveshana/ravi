const std = @import("std");
const Value = @import("ravi_vm_value").Value;

pub const Array = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    items: []Value = &.{},
    len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Array {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Array) void {
        if (self.items.len != 0) self.allocator.free(self.items);
        self.* = .{ .allocator = self.allocator };
    }

    fn ensureUnusedCapacity(self: *Array, additional: usize) !void {
        const required = std.math.add(usize, self.len, additional) catch return error.OutOfMemory;
        if (required <= self.items.len) return;
        var next = @max(self.items.len, 8);
        while (next < required) next = std.math.mul(usize, next, 2) catch return error.OutOfMemory;
        self.items = if (self.items.len == 0) try self.allocator.alloc(Value, next) else try self.allocator.realloc(self.items, next);
    }
};

pub const Dict = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    keys: []Value = &.{},
    values: []Value = &.{},
    occupied: []bool = &.{},
    len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Dict {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Dict) void {
        if (self.keys.len != 0) self.allocator.free(self.keys);
        if (self.values.len != 0) self.allocator.free(self.values);
        if (self.occupied.len != 0) self.allocator.free(self.occupied);
        self.* = .{ .allocator = self.allocator };
    }

    pub fn capacity(self: *const Dict) usize {
        return self.keys.len;
    }

    fn ensureInsertCapacity(self: *Dict) !void {
        if (self.keys.len != 0 and (self.len + 1) * 10 < self.keys.len * 7) return;
        const next = if (self.keys.len == 0) 8 else std.math.mul(usize, self.keys.len, 2) catch return error.OutOfMemory;
        const new_keys = try self.allocator.alloc(Value, next);
        errdefer self.allocator.free(new_keys);
        const new_values = try self.allocator.alloc(Value, next);
        errdefer self.allocator.free(new_values);
        const new_occupied = try self.allocator.alloc(bool, next);
        errdefer self.allocator.free(new_occupied);
        @memset(new_occupied, false);
        for (self.occupied, 0..) |is_occupied, index| if (is_occupied) insertRaw(new_keys, new_values, new_occupied, self.keys[index], self.values[index]);
        if (self.keys.len != 0) self.allocator.free(self.keys);
        if (self.values.len != 0) self.allocator.free(self.values);
        if (self.occupied.len != 0) self.allocator.free(self.occupied);
        self.keys = new_keys;
        self.values = new_values;
        self.occupied = new_occupied;
    }
};

fn hash(key: Value, capacity: usize) usize {
    return @intCast(key.hash() % capacity);
}

fn insertRaw(keys: []Value, values: []Value, occupied: []bool, key: Value, value: Value) void {
    var index = hash(key, keys.len);
    while (occupied[index]) : (index = (index + 1) % keys.len) {}
    keys[index] = key;
    values[index] = value;
    occupied[index] = true;
}

pub fn get(dict: *const Dict, key: Value) ?Value {
    if (dict.keys.len == 0) return null;
    var index = hash(key, dict.keys.len);
    for (0..dict.keys.len) |_| {
        if (!dict.occupied[index]) return null;
        if (Value.eql(dict.keys[index], key)) return dict.values[index];
        index = (index + 1) % dict.keys.len;
    }
    return null;
}

pub fn append(array: *Array, value: Value) !void {
    try array.ensureUnusedCapacity(1);
    array.items[array.len] = value;
    array.len += 1;
}
pub fn appendUnique(array: *Array, value: Value) !void {
    if (contains(array, value)) return;
    try append(array, value);
}
pub fn insert(array: *Array, position: usize, value: Value) !void {
    if (position > array.len) return error.InvalidIndex;
    try array.ensureUnusedCapacity(1);
    var i = array.len;
    while (i > position) : (i -= 1) array.items[i] = array.items[i - 1];
    array.items[position] = value;
    array.len += 1;
}
pub fn pop(array: *Array, position: usize) !Value {
    if (position >= array.len) return error.InvalidIndex;
    const value = array.items[position];
    std.mem.copyForwards(Value, array.items[position .. array.len - 1], array.items[position + 1 .. array.len]);
    array.len -= 1;
    return value;
}
pub fn contains(array: *const Array, value: Value) bool {
    for (array.items[0..array.len]) |item| if (Value.eql(item, value)) return true;
    return false;
}
pub fn clear(array: *Array) void {
    array.len = 0;
}
pub fn reverse(array: *Array) void {
    std.mem.reverse(Value, array.items[0..array.len]);
}
pub fn sort(array: *Array) void {
    std.mem.sort(Value, array.items[0..array.len], {}, struct {
        fn lessThan(_: void, left: Value, right: Value) bool {
            return left.isInt() and right.isInt() and left.asInt() < right.asInt();
        }
    }.lessThan);
}
pub fn put(dict: *Dict, key: Value, value: Value) !void {
    if (dict.keys.len != 0) {
        var index = hash(key, dict.keys.len);
        while (dict.occupied[index]) : (index = (index + 1) % dict.keys.len) {
            if (Value.eql(dict.keys[index], key)) {
                dict.values[index] = value;
                return;
            }
        }
    }
    try dict.ensureInsertCapacity();
    insertRaw(dict.keys, dict.values, dict.occupied, key, value);
    dict.len += 1;
}
pub fn remove(dict: *Dict, key: Value) !Value {
    if (dict.keys.len == 0) return error.MissingKey;
    var index = hash(key, dict.keys.len);
    for (0..dict.keys.len) |_| {
        if (!dict.occupied[index]) return error.MissingKey;
        if (Value.eql(dict.keys[index], key)) {
            const value = dict.values[index];
            dict.occupied[index] = false;
            dict.len -= 1;
            var next = (index + 1) % dict.keys.len;
            while (dict.occupied[next]) {
                const moved_key = dict.keys[next];
                const moved_value = dict.values[next];
                dict.occupied[next] = false;
                insertRaw(dict.keys, dict.values, dict.occupied, moved_key, moved_value);
                next = (next + 1) % dict.keys.len;
            }
            return value;
        }
        index = (index + 1) % dict.keys.len;
    }
    return error.MissingKey;
}

test "collections grow past their former fixed capacities" {
    var array = Array.init(std.testing.allocator);
    defer array.deinit();
    var dictionary = Dict.init(std.testing.allocator);
    defer dictionary.deinit();
    for (0..1000) |index| {
        try append(&array, Value.fromInt(@intCast(index)));
        try put(&dictionary, Value.fromInt(@intCast(index)), Value.fromInt(@intCast(index * 2)));
    }
    try std.testing.expectEqual(@as(usize, 1000), array.len);
    try std.testing.expectEqual(@as(i64, 1998), get(&dictionary, Value.fromInt(999)).?.asInt());
}
