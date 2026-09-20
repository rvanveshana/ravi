const std = @import("std");
const bytecode = @import("ravi_bytecode");
const compiler_mod = @import("ravi_compiler");
const diagnostics = @import("ravi_diagnostics");
const lexer = @import("ravi_lexer");
const parser_mod = @import("ravi_parser");
const semantic = @import("ravi_semantic");
const vm_mod = @import("ravi_vm");
const config = @import("ravi_config");
const dap = @import("ravi_dap");
const framing = @import("ravi_lsp_protocol");

fn initializeVm(allocator: std.mem.Allocator) !void {
    var vm = try vm_mod.Vm.initWithCollectorOptions(allocator, .{ .collection_threshold = 1, .stress = true });
    vm.deinit();
}

fn diagnosticText(code: []const u8, message: []const u8, line: usize, column: usize, source: []const u8) ![]u8 {
    return diagnostics.renderHuman(std.testing.allocator, "golden.rk", source, .{
        .code = code,
        .severity = .err,
        .message = message,
        .primary = .{ .start_offset = 0, .end_offset = 1, .line = line, .column = column },
    });
}

test "golden diagnostics cover lexical parsing semantic compile verify and runtime stages" {
    const cases = [_]struct { code: []const u8, message: []const u8, line: usize, column: usize, source: []const u8 }{
        .{ .code = "RAVI-LEX-001", .message = "InvalidCharacter", .line = 1, .column = 1, .source = "@\n" },
        .{ .code = "RAVI-PARSE-001", .message = "MissingName", .line = 1, .column = 1, .source = "kriya :\n" },
        .{ .code = "RAVI-SEM-001", .message = "UnknownName", .line = 1, .column = 1, .source = "kodu missing\n" },
        .{ .code = "RAVI-COMPILE-001", .message = "InvalidFunction", .line = 2, .column = 5, .source = "kriya main():\n    kodu 1\n" },
        .{ .code = "RAVI-VERIFY-001", .message = "InvalidJump", .line = 3, .column = 2, .source = "jump\n" },
        .{ .code = "RAVI-RUNTIME-001", .message = "DivisionByZero", .line = 4, .column = 7, .source = "answer = 1 / 0\n" },
    };
    for (cases) |case| {
        const rendered = try diagnosticText(case.code, case.message, case.line, case.column, case.source);
        defer std.testing.allocator.free(rendered);
        try std.testing.expect(std.mem.startsWith(u8, rendered, "golden.rk:"));
        try std.testing.expect(std.mem.indexOf(u8, rendered, case.code) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, case.message) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "^") != null);
    }
}

test "golden pipeline preserves Kannada and English source profiles" {
    const sources = [_]struct { language: config.SourceLanguage, text: []const u8 }{
        .{ .language = .kn, .text = "kriya main():\n    kodu 7\nmain()\n" },
        .{ .language = .en, .text = "# ravi: language=en\nfunction main():\n    return 7\nmain()\n" },
    };
    for (sources) |case| {
        var scan = try lexer.Lexer.initWithLanguage(std.testing.allocator, case.text, case.language);
        defer scan.deinit();
        const tokens = try scan.tokenize();
        var parser = parser_mod.Parser.initWithLanguage(std.testing.allocator, tokens, case.language);
        var module = try parser.parseRecovering();
        defer module.deinit();
        try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.len);
        var analyzer = semantic.Analyzer.init(std.testing.allocator);
        defer analyzer.deinit();
        try analyzer.analyzeWithLanguage(tokens, case.language);
        try analyzer.analyzeModule(&module);
        var compiler = compiler_mod.Compiler.initWithLanguage(std.testing.allocator, case.language);
        var chunk = try compiler.compileAstModule(&module);
        defer chunk.deinit();
        try chunk.verify();
        var vm = try vm_mod.Vm.init(std.testing.allocator);
        defer vm.deinit();
        try std.testing.expectEqual(@as(i64, 7), try vm.run(&chunk));
    }
}

test "nested runtime failures retain source locations and Ravi frames" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    chunk.setSourceLocation(.{ .start_offset = 10, .end_offset = 11, .line = 8, .column = 6 });
    try chunk.emit(.{ .op = .constant, .operand = 1 });
    try chunk.emit(.{ .op = .constant, .operand = 0 });
    try chunk.emit(.{ .op = .divide });
    try chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.DivisionByZero, vm.run(&chunk));
    const location = chunk.source_map.items[2];
    try std.testing.expectEqual(@as(usize, 8), location.line);
    try std.testing.expectEqual(@as(usize, 6), location.column);
}

test "verifier golden failure exposes the verifier stage" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.emit(.{ .op = .jump, .operand = -1 });
    try std.testing.expectError(error.InvalidJump, chunk.verify());
    const rendered = try diagnosticText("RAVI-VERIFY-001", "InvalidJump", 1, 1, "jump\n");
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("golden.rk:1:1: error[RAVI-VERIFY-001]: InvalidJump\n", rendered[0 .. std.mem.indexOfScalar(u8, rendered, '\n').? + 1]);
}

test "DAP serializes scopes variables evaluation and serves framed requests" {
    const Reader = struct {
        bytes: []const u8,
        done: bool = false,
        pub fn read(self: *@This(), buffer: []u8) !usize {
            if (self.done) return 0;
            self.done = true;
            @memcpy(buffer[0..self.bytes.len], self.bytes);
            return self.bytes.len;
        }
    };
    const Writer = struct {
        bytes: std.ArrayListUnmanaged(u8) = .empty,
        allocator: std.mem.Allocator,
        pub fn writeAll(self: *@This(), bytes: []const u8) !void {
            try self.bytes.appendSlice(self.allocator, bytes);
        }
    };
    var state = @import("ravi_debug").Debugger.init(std.testing.allocator);
    defer state.deinit();
    const values = [_]@import("ravi_debug").Variable{.{ .name = "answer", .value = 42 }};
    try state.updateScopes(&[_]@import("ravi_debug").Scope{.{ .name = "Locals", .variables = &values }});
    var adapter = dap.Adapter.init(std.testing.allocator, &state);
    const scopes = try adapter.dispatch("{\"command\":\"scopes\"}");
    defer std.testing.allocator.free(scopes);
    try std.testing.expect(std.mem.indexOf(u8, scopes, "Locals") != null);
    const variables = try adapter.dispatch("{\"command\":\"variables\",\"variablesReference\":1}");
    defer std.testing.allocator.free(variables);
    try std.testing.expect(std.mem.indexOf(u8, variables, "answer") != null);
    const evaluated = try adapter.dispatch("{\"command\":\"evaluate\",\"expression\":\"answer\"}");
    defer std.testing.allocator.free(evaluated);
    try std.testing.expect(std.mem.indexOf(u8, evaluated, "\"result\":\"42\"") != null);

    const first = try framing.encode(std.testing.allocator, "{\"command\":\"initialize\"}");
    defer std.testing.allocator.free(first);
    var reader = Reader{ .bytes = first };
    var writer = Writer{ .allocator = std.testing.allocator };
    defer writer.bytes.deinit(std.testing.allocator);
    try adapter.serve(&reader, &writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.bytes.items, "Content-Length:") != null);
}

test "VM stress collection reclaims transient strings without stale handles" {
    var chunk = bytecode.Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    const string_index = try chunk.addString("transient");
    for (0..128) |_| {
        try chunk.emit(.{ .op = .make_string, .operand = @intCast(string_index) });
        try chunk.emit(.{ .op = .pop });
    }
    try chunk.emit(.{ .op = .halt });
    var vm = try vm_mod.Vm.initWithCollectorOptions(std.testing.allocator, .{ .collection_threshold = 1, .stress = true });
    defer vm.deinit();
    _ = try vm.runValue(&chunk);
    try std.testing.expect(vm.collectorStatistics().collections > 0);
    try vm.collectGarbage();
    try std.testing.expect(vm.collectorStatistics().live == 0);
}

test "VM and managed runtime initialization propagates every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initializeVm, .{});
}
