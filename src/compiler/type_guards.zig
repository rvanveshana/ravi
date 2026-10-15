const std = @import("std");
const bytecode = @import("ravi_bytecode");

pub fn emit(chunk: *bytecode.Chunk, annotation: ?[]const u8) !void {
    const name = annotation orelse return;
    const opcode: ?bytecode.OpCode = if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "integer")) .guard_integer else if (std.mem.eql(u8, name, "float")) .guard_float else if (std.mem.eql(u8, name, "bool") or std.mem.eql(u8, name, "boolean")) .guard_boolean else if (std.mem.eql(u8, name, "str") or std.mem.eql(u8, name, "string")) .guard_string else null;
    if (opcode) |op| try chunk.emit(.{ .op = op });
}
