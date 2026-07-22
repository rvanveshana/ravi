const std = @import("std");

pub const Capacity = 64;
pub const Array = struct { items: [Capacity]i64 = undefined, len: usize = 0 };
pub const DictCapacity = 64;
pub const Dict = struct {
    keys: [DictCapacity]i64 = undefined,
    values: [DictCapacity]i64 = undefined,
    occupied: [DictCapacity]bool = @splat(false),
    len: usize = 0,
};

fn hash(key: i64) usize {
    var x: u64 = @bitCast(key);
    x ^= x >> 33;
    x *%= 0xff51afd7ed558ccd;
    x ^= x >> 33;
    return @intCast(x % DictCapacity);
}

pub fn get(dict: *const Dict, key: i64) ?i64 {
    var index = hash(key);
    for (0..DictCapacity) |_| {
        if (!dict.occupied[index]) return null;
        if (dict.keys[index] == key) return dict.values[index];
        index = (index + 1) % DictCapacity;
    }
    return null;
}

pub fn append(array: *Array, value: i64) !void {
    if (array.len >= Capacity) return error.CollectionFull;
    array.items[array.len] = value;
    array.len += 1;
}
pub fn appendUnique(array: *Array, value: i64) !void {
    if (contains(array, value)) return;
    try append(array, value);
}
pub fn insert(array: *Array, position: usize, value: i64) !void {
    if (array.len >= Capacity or position > array.len) return error.InvalidIndex;
    var i = array.len;
    while (i > position) : (i -= 1) array.items[i] = array.items[i - 1];
    array.items[position] = value;
    array.len += 1;
}
pub fn pop(array: *Array, position: usize) !i64 {
    if (position >= array.len) return error.InvalidIndex;
    const value = array.items[position];
    var i = position;
    while (i + 1 < array.len) : (i += 1) array.items[i] = array.items[i + 1];
    array.len -= 1;
    return value;
}
pub fn contains(array: *const Array, value: i64) bool {
    for (array.items[0..array.len]) |item| if (item == value) return true;
    return false;
}
pub fn clear(array: *Array) void {
    array.len = 0;
}
pub fn reverse(array: *Array) void {
    if (array.len < 2) return;
    var left: usize = 0;
    var right: usize = array.len - 1;
    while (left < right) : ({
        left += 1;
        right -= 1;
    }) {
        std.mem.swap(i64, &array.items[left], &array.items[right]);
    }
}
pub fn sort(array: *Array) void {
    if (array.len < 2) return;
    var i: usize = 1;
    while (i < array.len) : (i += 1) {
        const value = array.items[i];
        var j = i;
        while (j > 0 and array.items[j - 1] > value) : (j -= 1) array.items[j] = array.items[j - 1];
        array.items[j] = value;
    }
}
pub fn put(dict: *Dict, key: i64, value: i64) !void {
    if (dict.len >= DictCapacity) return error.CollectionFull;
    var index = hash(key);
    while (dict.occupied[index]) : (index = (index + 1) % DictCapacity) {
        if (dict.keys[index] == key) {
            dict.values[index] = value;
            return;
        }
    }
    dict.keys[index] = key;
    dict.values[index] = value;
    dict.occupied[index] = true;
    dict.len += 1;
}
pub fn remove(dict: *Dict, key: i64) !i64 {
    var index = hash(key);
    for (0..DictCapacity) |_| {
        if (!dict.occupied[index]) return error.MissingKey;
        if (dict.keys[index] == key) {
            const value = dict.values[index];
            dict.occupied[index] = false;
            dict.len -= 1;
            // Reinsert the following cluster so lookups remain valid.
            var next = (index + 1) % DictCapacity;
            while (dict.occupied[next]) {
                const moved_key = dict.keys[next];
                const moved_value = dict.values[next];
                dict.occupied[next] = false;
                dict.len -= 1;
                try put(dict, moved_key, moved_value);
                next = (next + 1) % DictCapacity;
            }
            return value;
        }
        index = (index + 1) % DictCapacity;
    }
    return error.MissingKey;
}
