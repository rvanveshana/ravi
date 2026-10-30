const std = @import("std");
const bytecode = @import("ravi_bytecode");

/// An owned immutable snapshot. Worker execution never observes later source
/// chunk mutations and needs no repeated verification on resume.
pub const Program = struct {
    arena: std.heap.ArenaAllocator,
    chunk: bytecode.Chunk,
    source: *const bytecode.Chunk,

    pub fn create(source: *const bytecode.Chunk) !*Program {
        const owner = std.heap.smp_allocator;
        const self = try owner.create(Program);
        errdefer owner.destroy(self);
        self.arena = std.heap.ArenaAllocator.init(owner);
        errdefer self.arena.deinit();
        const allocator = self.arena.allocator();
        self.chunk = bytecode.Chunk.init(allocator);
        self.source = source;
        inline for (.{ "code", "floats", "source_map", "root_map", "functions", "classes", "methods", "captures", "formats" }) |field|
            try @field(self.chunk, field).appendSlice(allocator, @field(source, field).items);
        for (source.strings.items) |text| try self.chunk.strings.append(allocator, try allocator.dupe(u8, text));
        for (self.chunk.formats.items) |*format| format.template = try allocator.dupe(u8, format.template);
        for (self.chunk.functions.items) |*function| {
            function.name = try allocator.dupe(u8, function.name);
            if (function.method_name) |name| function.method_name = try allocator.dupe(u8, name);
        }
        for (self.chunk.classes.items) |*class| class.name = try allocator.dupe(u8, class.name);
        for (self.chunk.methods.items) |*method| method.name = try allocator.dupe(u8, method.name);
        try self.chunk.verifyWithAllocator(owner);
        return self;
    }

    pub fn destroy(self: *Program) void {
        self.arena.deinit();
        std.heap.smp_allocator.destroy(self);
    }
};
