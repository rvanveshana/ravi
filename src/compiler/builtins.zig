const std = @import("std");
const config = @import("ravi_config");

pub fn functionReference(comptime Error: type, compiler: anytype, chunk: anytype, module: anytype, name: []const u8) Error!bool {
    const index = compiler.findAstFunction(module, name) orelse return false;
    if (chunk.functions.items[index].capture_count != 0) return error.InvalidFunction;
    try chunk.emit(.{ .op = .make_function, .operand = @intCast(index) });
    return true;
}

pub fn hostCall(comptime Error: type, compiler: anytype, chunk: anytype, module: anytype, name: []const u8, call: anytype, names: anytype, expression: anytype) Error!bool {
    const id = config.hostBuiltin(name) orelse return false;
    const spec = config.host_builtins[@intFromEnum(id)];
    if (call.arg_count != spec.arguments or call.keyword_count != 0) return error.InvalidFunction;
    for (module.call_args.items[call.first_arg .. call.first_arg + call.arg_count]) |argument| try expression(Error, compiler, chunk, module, argument, names);
    try chunk.emit(.{ .op = .host_call, .operand = @as(i64, @intFromEnum(id)) * 256 + spec.arguments });
    return true;
}

pub fn isPrint(language: config.SourceLanguage, name: []const u8) bool {
    return if (language == .kn) std.mem.eql(u8, name, "mudrisu") else std.mem.eql(u8, name, "print");
}

pub fn isType(language: config.SourceLanguage, name: []const u8) bool {
    return if (language == .kn) std.mem.eql(u8, name, "vidha") else std.mem.eql(u8, name, "type");
}

pub fn isSleep(language: config.SourceLanguage, name: []const u8) bool {
    return if (language == .kn) std.mem.eql(u8, name, "malagu") else std.mem.eql(u8, name, "sleep");
}

pub fn method(language: config.SourceLanguage, name: []const u8, english: []const u8, kannada: []const u8) bool {
    return if (language == .kn) std.mem.eql(u8, name, kannada) else std.mem.eql(u8, name, english);
}
