const std = @import("std");
const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");
const config = @import("ravi_config");
const Lexer = @import("ravi_lexer").Lexer;
const Parser = @import("ravi_parser").Parser;
const Analyzer = @import("ravi_semantic").Analyzer;
const Compiler = @import("ravi_compiler").Compiler;
const Optimizer = @import("ravi_optimizer").Optimizer;

/// One executable pipeline shared by the CLI and integration tests.
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    last_location: bytecode.SourceLocation = .{ .start_offset = 0, .end_offset = 0, .line = 1, .column = 1 },

    pub fn compile(self: *Pipeline, module: *const ast.Module) !bytecode.Chunk {
        var analyzer = Analyzer.init(self.allocator);
        defer analyzer.deinit();
        analyzer.analyzeModule(module) catch |err| {
            if (analyzer.last_span) |span| self.last_location = .{ .source_id = span.source_id, .start_offset = span.start_offset, .end_offset = span.end_offset, .line = span.line, .column = 1 };
            return err;
        };
        var compiler = Compiler.initWithLanguage(self.allocator, module.language);
        var chunk = compiler.lowerModule(module) catch |err| {
            self.last_location = compiler.last_location;
            return err;
        };
        errdefer chunk.deinit();
        try chunk.verify();
        _ = try Optimizer.optimize(&chunk);
        try chunk.verify();
        return chunk;
    }

    pub fn compileSource(self: *Pipeline, source: []const u8, language: config.SourceLanguage) !bytecode.Chunk {
        var lexer = try Lexer.initWithLanguage(self.allocator, source, language);
        defer lexer.deinit();
        const tokens = try lexer.tokenize();
        var parser = Parser.initWithLanguage(self.allocator, tokens, language);
        var module = try parser.parseRecovering();
        defer module.deinit();
        if (module.diagnostics.items.len != 0) return error.InvalidExpression;
        return self.compile(&module);
    }
};

test "shared pipeline rejects unresolved names" {
    var pipeline = Pipeline{ .allocator = std.testing.allocator };
    try std.testing.expectError(error.InvalidName, pipeline.compileSource("print(missing)\n", .en));
}

test "optimization preserves integer literal errors" {
    var pipeline = Pipeline{ .allocator = std.testing.allocator };
    var chunk = try pipeline.compileSource("print(140737488355328 - 1)\n", .en);
    defer chunk.deinit();
    try std.testing.expectEqual(@as(i64, 140737488355328), chunk.code.items[0].operand);
}

test "annotations reject known mismatches and guard dynamic calls" {
    var pipeline = Pipeline{ .allocator = std.testing.allocator };
    try std.testing.expectError(error.TypeMismatch, pipeline.compileSource("function f(x: int):\n    return x\nf(\"oops\")\n", .en));
    var chunk = try pipeline.compileSource("function f(x: int):\n    return x\ng = f\ng(\"oops\")\n", .en);
    defer chunk.deinit();
    var vm = try @import("ravi_vm").Vm.init(std.testing.allocator);
    defer vm.deinit();
    try std.testing.expectError(error.TypeGuardFailed, vm.run(&chunk));
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    var pipeline = Pipeline{ .allocator = allocator };
    var chunk = try pipeline.compileSource("function f(x: int):\n    return x + 1\nf(41)\n", .en);
    defer chunk.deinit();
}

test "shared compilation cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
