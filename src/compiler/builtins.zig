const std = @import("std");
const config = @import("ravi_config");

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
