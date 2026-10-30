//! Central language configuration.  Front-end and runtime code should import
//! this module instead of embedding spelling or resource limits locally.

pub const language_name = "Ravi Kannada";
pub const source_extension = ".rk";
pub const SourceLanguage = enum { kn, en };
pub const LanguageHeaderError = error{InvalidLanguageHeader};
pub const spaces_per_indent: usize = 4;
pub const tab_width: usize = 4;
pub const max_identifier_bytes: usize = 256;
pub const max_string_bytes: usize = 16 * 1024 * 1024;
pub const HostBuiltin = enum(u8) {
    task_cancel,
    task_release,
    task_done,
    channel_create,
    channel_send,
    channel_recv,
    channel_close,
    read_text,
    write_text,
    path_join,
    path_basename,
    path_dirname,
    clock_mono,
    clock_wall,
    json_encode,
    json_decode,
    bytes_encode,
    bytes_decode,
    log,
    assert_equal,
    env_get,
    task_wait_timeout,
    channel_send_timeout,
    channel_recv_timeout,
};
pub const HostSpec = struct { name: []const u8, arguments: u8, blocking: bool = false };
pub const host_builtins = [_]HostSpec{
    .{ .name = "__ravi_task_cancel", .arguments = 1 },   .{ .name = "__ravi_task_release", .arguments = 1 },                .{ .name = "__ravi_task_done", .arguments = 1 },
    .{ .name = "__ravi_channel", .arguments = 1 },       .{ .name = "__ravi_send", .arguments = 2 },                        .{ .name = "__ravi_receive", .arguments = 1 },
    .{ .name = "__ravi_close_channel", .arguments = 1 }, .{ .name = "__ravi_read_text", .arguments = 1, .blocking = true }, .{ .name = "__ravi_write_text", .arguments = 2, .blocking = true },
    .{ .name = "__ravi_path_join", .arguments = 2 },     .{ .name = "__ravi_basename", .arguments = 1 },                    .{ .name = "__ravi_dirname", .arguments = 1 },
    .{ .name = "__ravi_monotonic", .arguments = 0 },     .{ .name = "__ravi_wall_time", .arguments = 0 },                   .{ .name = "__ravi_json_encode", .arguments = 1 },
    .{ .name = "__ravi_json_decode", .arguments = 1 },   .{ .name = "__ravi_encode_utf8", .arguments = 1 },                 .{ .name = "__ravi_decode_utf8", .arguments = 1 },
    .{ .name = "__ravi_log", .arguments = 2 },           .{ .name = "__ravi_assert_equal", .arguments = 2 },                .{ .name = "__ravi_env", .arguments = 1, .blocking = true },
    .{ .name = "__ravi_wait_for", .arguments = 2 },      .{ .name = "__ravi_send_for", .arguments = 3 },                    .{ .name = "__ravi_receive_for", .arguments = 2 },
};
pub fn hostBuiltin(name: []const u8) ?HostBuiltin {
    for (host_builtins, 0..) |spec, id| if (std.mem.eql(u8, name, spec.name)) return @enumFromInt(id);
    return null;
}

comptime {
    if (host_builtins.len != @typeInfo(HostBuiltin).@"enum".field_names.len)
        @compileError("host builtin descriptors must match the opcode registry");
}

pub const Keyword = struct {
    spelling: []const u8,
    canonical: []const u8,
};

pub const keywords = [_]Keyword{
    .{ .spelling = "adre", .canonical = "if" },
    .{ .spelling = "inadre", .canonical = "elif" },
    .{ .spelling = "illa", .canonical = "else" },
    .{ .spelling = "vargu", .canonical = "while" },
    .{ .spelling = "prati", .canonical = "for" },
    .{ .spelling = "nillu", .canonical = "break" },
    .{ .spelling = "munde", .canonical = "continue" },
    .{ .spelling = "bidu", .canonical = "pass" },
    .{ .spelling = "kriya", .canonical = "function" },
    .{ .spelling = "horabidu", .canonical = "spawn" },
    .{ .spelling = "kaayu", .canonical = "wait" },
    .{ .spelling = "kodu", .canonical = "return" },
    .{ .spelling = "taru", .canonical = "yield" },
    .{ .spelling = "nodu", .canonical = "try" },
    .{ .spelling = "tappu", .canonical = "except" },
    .{ .spelling = "kone", .canonical = "finally" },
    .{ .spelling = "yese", .canonical = "raise" },
    .{ .spelling = "tago", .canonical = "import" },
    .{ .spelling = "inda", .canonical = "from" },
    .{ .spelling = "jote", .canonical = "with" },
    .{ .spelling = "aagi", .canonical = "as" },
    .{ .spelling = "true", .canonical = "true" },
    .{ .spelling = "false", .canonical = "false" },
    .{ .spelling = "none", .canonical = "none" },
    .{ .spelling = "mattu", .canonical = "and" },
    .{ .spelling = "athva", .canonical = "or" },
    .{ .spelling = "alla", .canonical = "not" },
    .{ .spelling = "alli", .canonical = "in" },
    .{ .spelling = "ide", .canonical = "is" },
    .{ .spelling = "roopa", .canonical = "class" },
    .{ .spelling = "ella", .canonical = "global" },
    .{ .spelling = "saarva", .canonical = "public" },
    .{ .spelling = "swanta", .canonical = "private" },
    .{ .spelling = "vansha", .canonical = "protected" },
    .{ .spelling = "olage", .canonical = "internal" },
};

pub const english_keywords = [_]Keyword{
    .{ .spelling = "if", .canonical = "if" },               .{ .spelling = "elif", .canonical = "elif" },         .{ .spelling = "else", .canonical = "else" },
    .{ .spelling = "while", .canonical = "while" },         .{ .spelling = "for", .canonical = "for" },           .{ .spelling = "break", .canonical = "break" },
    .{ .spelling = "continue", .canonical = "continue" },   .{ .spelling = "pass", .canonical = "pass" },         .{ .spelling = "function", .canonical = "function" },
    .{ .spelling = "spawn", .canonical = "spawn" },         .{ .spelling = "wait", .canonical = "wait" },         .{ .spelling = "return", .canonical = "return" },
    .{ .spelling = "yield", .canonical = "yield" },         .{ .spelling = "try", .canonical = "try" },           .{ .spelling = "except", .canonical = "except" },
    .{ .spelling = "finally", .canonical = "finally" },     .{ .spelling = "raise", .canonical = "raise" },       .{ .spelling = "import", .canonical = "import" },
    .{ .spelling = "from", .canonical = "from" },           .{ .spelling = "with", .canonical = "with" },         .{ .spelling = "as", .canonical = "as" },
    .{ .spelling = "true", .canonical = "true" },           .{ .spelling = "false", .canonical = "false" },       .{ .spelling = "none", .canonical = "none" },
    .{ .spelling = "and", .canonical = "and" },             .{ .spelling = "or", .canonical = "or" },             .{ .spelling = "not", .canonical = "not" },
    .{ .spelling = "in", .canonical = "in" },               .{ .spelling = "is", .canonical = "is" },             .{ .spelling = "class", .canonical = "class" },
    .{ .spelling = "global", .canonical = "global" },       .{ .spelling = "public", .canonical = "public" },     .{ .spelling = "private", .canonical = "private" },
    .{ .spelling = "protected", .canonical = "protected" }, .{ .spelling = "internal", .canonical = "internal" },
};

pub fn keywordCanonical(spelling: []const u8) ?[]const u8 {
    for (keywords) |keyword| {
        if (std.mem.eql(u8, keyword.spelling, spelling)) return keyword.canonical;
    }
    return null;
}

pub fn keywordCanonicalFor(language: SourceLanguage, spelling: []const u8) ?[]const u8 {
    const table = if (language == .kn) keywords[0..] else english_keywords[0..];
    for (table) |keyword| if (std.mem.eql(u8, keyword.spelling, spelling)) return keyword.canonical;
    return null;
}

pub fn keywordIsCanonical(language: SourceLanguage, spelling: []const u8, canonical: []const u8) bool {
    return std.mem.eql(u8, keywordCanonicalFor(language, spelling) orelse "", canonical);
}

pub fn belongsToOtherLanguage(language: SourceLanguage, spelling: []const u8) bool {
    const other = if (language == .kn) english_keywords[0..] else keywords[0..];
    for (other) |keyword| if (std.mem.eql(u8, keyword.spelling, spelling)) return true;
    return false;
}

pub fn languageFromHeader(source: []const u8) LanguageHeaderError!?SourceLanguage {
    const end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
    const line = std.mem.trim(u8, source[0..end], " \t\r");
    const prefix = "# ravi: language=";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const value = line[prefix.len..];
    if (std.mem.eql(u8, value, "kn")) return .kn;
    if (std.mem.eql(u8, value, "en")) return .en;
    return error.InvalidLanguageHeader;
}

const std = @import("std");
