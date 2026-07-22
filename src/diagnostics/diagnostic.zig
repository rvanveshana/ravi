pub const Severity = enum { info, warning, err };
pub const Diagnostic = struct { severity: Severity, message: []const u8, line: usize, column: usize };
