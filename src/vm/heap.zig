const std = @import("std");
const collections = @import("ravi_vm_collections");
const frames = @import("frames.zig");

pub const ManagedString = struct { bytes: []u8 };
pub const ManagedArray = collections.Array;
pub const ManagedDict = collections.Dict;
pub const ManagedClosure = frames.Closure;
pub const ManagedCell = frames.Cell;
pub const ManagedInstance = struct { class_index: usize, fields: collections.Dict };
pub const ManagedException = struct { name: []u8 };

pub fn destroyString(allocator: std.mem.Allocator, string: *ManagedString) void {
    allocator.free(string.bytes);
    allocator.destroy(string);
}

pub fn destroyArray(allocator: std.mem.Allocator, array: *ManagedArray) void {
    array.deinit();
    allocator.destroy(array);
}

pub fn destroyDict(allocator: std.mem.Allocator, dict: *ManagedDict) void {
    dict.deinit();
    allocator.destroy(dict);
}

pub fn destroyClosure(allocator: std.mem.Allocator, closure: *ManagedClosure) void {
    closure.deinit(allocator);
    allocator.destroy(closure);
}

pub fn destroyCell(allocator: std.mem.Allocator, cell: *ManagedCell) void {
    allocator.destroy(cell);
}

pub fn destroyInstance(allocator: std.mem.Allocator, instance: *ManagedInstance) void {
    instance.fields.deinit();
    allocator.destroy(instance);
}

pub fn destroyException(allocator: std.mem.Allocator, exception: *ManagedException) void {
    allocator.free(exception.name);
    allocator.destroy(exception);
}
