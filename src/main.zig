const std = @import("std");
const Lexer = @import("ravi_lexer").Lexer;
const TokenKind = @import("ravi_lexer").TokenKind;
const Parser = @import("parser/parser.zig").Parser;
const Analyzer = @import("semantic/analyzer.zig").Analyzer;
const gc = @import("memory/gc.zig");
const Compiler = @import("ravi_compiler").Compiler;
const Vm = @import("ravi_vm").Vm;
const RuntimeValue = @import("ravi_value").Value;
const Backend = @import("ravi_backend").Backend;
const Optimizer = @import("ravi_optimizer").Optimizer;
const Debugger = @import("ravi_debug").Debugger;
const Scheduler = @import("ravi_scheduler").Scheduler;
const SyntaxTree = @import("ravi_syntax").SyntaxTree;
const config = @import("ravi_config");

const sample =
    "math inda add tago\n" ++
    "kriya calculate(a: int, b: int):\n" ++
    "    nodu:\n" ++
    "        adre a > 10:\n" ++
    "            kodu add(a, b)\n" ++
    "        illa:\n" ++
    "            kodu a\n" ++
    "    tappu:\n" ++
    "        kodu none\n";

pub fn main(init: std.process.Init) !void {
    var collector = gc.Collector.init(std.heap.page_allocator);
    defer collector.deinit();
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, collector.allocator());
    defer args.deinit();
    _ = args.next();
    const mode = args.next() orelse "check";
    var path: ?[]const u8 = null;
    var language_override: ?config.SourceLanguage = null;
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--lang")) {
            const name = args.next() orelse {
                std.debug.print("missing language after --lang\n", .{});
                return;
            };
            if (std.mem.eql(u8, name, "kn")) language_override = .kn else if (std.mem.eql(u8, name, "en")) language_override = .en else {
                std.debug.print("unknown language: {s}\n", .{name});
                return;
            }
        } else path = argument;
    }
    const source = if (path) |file_path| try std.Io.Dir.cwd().readFileAlloc(init.io, file_path, collector.allocator(), .limited(16 * 1024 * 1024)) else sample;
    const language = if (language_override) |selected| selected else (config.languageFromHeader(source) catch |err| {
        std.debug.print("language header error: {s}\n", .{@errorName(err)});
        return;
    }) orelse .kn;
    var lexer = try Lexer.initWithLanguage(collector.allocator(), source, language);
    defer lexer.deinit();
    const tokens = lexer.tokenize() catch |err| {
        std.debug.print("lex error: {s}\n", .{@errorName(err)});
        return;
    };
    if (std.mem.eql(u8, mode, "tokens")) {
        for (tokens) |token| std.debug.print("{d}:{d} {s} {s}\n", .{ token.line, token.column, @tagName(token.kind), token.lexeme });
        return;
    }
    var parser = Parser.initWithLanguage(collector.allocator(), tokens, language);
    var module = parser.parseRecovering() catch |err| {
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        return;
    };
    defer module.deinit();
    if (module.diagnostics.items.len != 0) {
        for (module.diagnostics.items) |diagnostic| {
            const token = if (diagnostic.span.first < tokens.len) tokens[diagnostic.span.first] else tokens[tokens.len - 1];
            std.debug.print("parse error at {d}:{d} (tokens {d}-{d}): {s}\n", .{ diagnostic.span.line, token.column, diagnostic.span.first, diagnostic.span.last, diagnostic.message });
        }
        return;
    }
    var analyzer = Analyzer.init(collector.allocator());
    defer analyzer.deinit();
    analyzer.analyzeWithLanguage(tokens, language) catch |err| {
        std.debug.print("semantic error: {s}\n", .{@errorName(err)});
        return;
    };
    analyzer.analyzeModule(&module) catch |err| {
        std.debug.print("semantic error: {s}\n", .{@errorName(err)});
        return;
    };
    if (std.mem.eql(u8, mode, "run")) {
        var compiler = Compiler.initWithLanguage(collector.allocator(), language);
        var chunk = compiler.compileProgram(tokens) catch |err| {
            std.debug.print("compile error: {s}\n", .{@errorName(err)});
            return;
        };
        defer chunk.deinit();
        var vm = Vm{};
        const result = vm.run(&chunk) catch |err| {
            std.debug.print("runtime error: {s}\n", .{@errorName(err)});
            for (vm.trace[0..vm.trace_count]) |frame| std.debug.print("  at {s} (bytecode {d})\n", .{ frame.function, frame.instruction });
            return;
        };
        if (!vm.pub_printed) std.debug.print("{d}\n", .{result});
        return;
    }
    std.debug.print("valid Ravi module: {d} syntax nodes\n", .{module.statements.items.len});
    _ = TokenKind; // Keep the token contract available to the CLI module.
    _ = RuntimeValue; // Keep the dynamic runtime representation linked.
    _ = Backend;
    _ = Optimizer;
    _ = Debugger;
    _ = Scheduler;
    var syntax = try SyntaxTree.fromTokens(collector.allocator(), source, tokens);
    defer syntax.deinit();
}
