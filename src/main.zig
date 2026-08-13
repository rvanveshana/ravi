const std = @import("std");
const Lexer = @import("ravi_lexer").Lexer;
const TokenKind = @import("ravi_lexer").TokenKind;
const Parser = @import("ravi_parser").Parser;
const Analyzer = @import("semantic/analyzer.zig").Analyzer;
const gc = @import("ravi_gc");
const hir_pipeline = @import("ravi_hir_pipeline");
const bytecode = @import("ravi_bytecode");
const Vm = @import("ravi_vm").Vm;
const Backend = @import("ravi_backend").Backend;
const Optimizer = @import("ravi_optimizer").Optimizer;
const debug_mod = @import("ravi_debug");
const Debugger = debug_mod.Debugger;
const Scheduler = @import("ravi_scheduler").Scheduler;
const SyntaxTree = @import("ravi_syntax").SyntaxTree;
const SourceManager = @import("ravi_source").Manager;
const diagnostics = @import("ravi_diagnostics");
const formatter = @import("ravi_formatter");
const ModuleLoader = @import("ravi_loader").Loader;
const config = @import("ravi_config");
const version = "0.1.0-dev";
const DiagnosticFormat = enum { human, compact, json };
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
    const first_arg = args.next() orelse "check";
    if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
        printHelp();
        return;
    }
    if (std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "-V")) {
        std.debug.print("ravi {s}\n", .{version});
        return;
    }
    var mode: []const u8 = "check";
    var path: ?[]const u8 = null;
    var language_override: ?config.SourceLanguage = null;
    var diagnostic_format: DiagnosticFormat = .human;
    if (std.mem.eql(u8, first_arg, "check") or std.mem.eql(u8, first_arg, "run") or std.mem.eql(u8, first_arg, "trace") or std.mem.eql(u8, first_arg, "tokens") or std.mem.eql(u8, first_arg, "bytecode") or std.mem.eql(u8, first_arg, "fmt") or std.mem.eql(u8, first_arg, "fmt-check")) {
        mode = first_arg;
    } else if (std.mem.eql(u8, first_arg, "--lang")) {
        const name = args.next() orelse {
            std.debug.print("missing language after --lang\n", .{});
            std.process.exit(2);
        };
        if (std.mem.eql(u8, name, "kn")) language_override = .kn else if (std.mem.eql(u8, name, "en")) language_override = .en else {
            std.debug.print("unknown language: {s}\n", .{name});
            std.process.exit(2);
        }
    } else {
        path = first_arg;
        mode = "run";
    }
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--lang")) {
            const name = args.next() orelse {
                std.debug.print("missing language after --lang\n", .{});
                std.process.exit(2);
            };
            if (std.mem.eql(u8, name, "kn")) language_override = .kn else if (std.mem.eql(u8, name, "en")) language_override = .en else {
                std.debug.print("unknown language: {s}\n", .{name});
                std.process.exit(2);
            }
        } else if (std.mem.eql(u8, argument, "--diagnostic-format")) {
            const name = args.next() orelse {
                std.debug.print("missing value after --diagnostic-format\n", .{});
                std.process.exit(2);
            };
            diagnostic_format = std.meta.stringToEnum(DiagnosticFormat, name) orelse {
                std.debug.print("unknown diagnostic format: {s}\n", .{name});
                std.process.exit(2);
            };
        } else if (path == null) path = argument;
    }
    const loaded_source = if (path) |file_path| try std.Io.Dir.cwd().readFileAlloc(init.io, file_path, collector.allocator(), .limited(16 * 1024 * 1024)) else sample;
    var source_manager = SourceManager.init(collector.allocator());
    defer source_manager.deinit();
    const source_id = try source_manager.add(path orelse "<sample>", loaded_source);
    const managed_source = source_manager.get(source_id).?;
    const source = managed_source.text;
    if (std.mem.eql(u8, mode, "fmt") or std.mem.eql(u8, mode, "fmt-check")) {
        const formatted = try formatter.format(collector.allocator(), source);
        defer collector.allocator().free(formatted);
        if (std.mem.eql(u8, mode, "fmt-check")) {
            if (!std.mem.eql(u8, source, formatted)) std.process.exit(1);
        } else if (path) |file_path| {
            try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = file_path, .data = formatted });
        } else {
            std.debug.print("{s}", .{formatted});
        }
        return;
    }
    const language = if (language_override) |selected| selected else (config.languageFromHeader(source) catch |err| {
        std.debug.print("language header error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    }) orelse .kn;
    var lexer = try Lexer.initWithLanguage(collector.allocator(), source, language);
    defer lexer.deinit();
    const tokens = lexer.tokenize() catch |err| {
        printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-LEX-001", @errorName(err), .{ .start_offset = lexer.error_offset, .end_offset = @min(lexer.error_offset + 1, source.len), .line = lexer.error_line, .column = lexer.error_column });
        std.process.exit(1);
    };
    if (std.mem.eql(u8, mode, "tokens")) {
        for (tokens) |token| std.debug.print("{d}:{d} {s} {s}\n", .{ token.line, token.column, @tagName(token.kind), token.lexeme });
        return;
    }
    var parser = Parser.initWithLanguage(collector.allocator(), tokens, language);
    var module = parser.parseRecovering() catch |err| {
        const error_token = tokens[@min(parser.index, tokens.len - 1)];
        printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-PARSE-001", @errorName(err), tokenLocation(error_token));
        std.process.exit(1);
    };
    defer module.deinit();
    if (module.diagnostics.items.len != 0) {
        for (module.diagnostics.items) |diagnostic| {
            const token = if (diagnostic.span.first < tokens.len) tokens[diagnostic.span.first] else tokens[tokens.len - 1];
            printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-PARSE-002", diagnostic.message, tokenLocation(token));
        }
        std.process.exit(1);
    }
    var analyzer = Analyzer.init(collector.allocator());
    defer analyzer.deinit();
    analyzer.analyzeWithLanguage(tokens, language) catch |err| {
        printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-SEM-001", @errorName(err), tokenLocation(analyzer.last_token orelse tokens[0]));
        std.process.exit(1);
    };
    analyzer.analyzeModule(&module) catch |err| {
        printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-SEM-002", @errorName(err), tokenLocation(tokens[0]));
        std.process.exit(1);
    };
    if (std.mem.eql(u8, mode, "run") or std.mem.eql(u8, mode, "trace") or std.mem.eql(u8, mode, "bytecode")) {
        if (std.mem.eql(u8, mode, "run")) if (path) |file_path| {
            var imports_loaded = true;
            runWithImports(collector.allocator(), init.io, file_path) catch |err| switch (err) {
                error.FileNotFound => imports_loaded = false,
                else => return err,
            };
            if (imports_loaded) return;
        };
        var chunk: bytecode.Chunk = undefined;
        chunk = hir_pipeline.lower(collector.allocator(), &module) catch |err| {
            printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-HIR-001", @errorName(err), .{ .start_offset = 0, .end_offset = source.len, .line = 1, .column = 1 });
            std.process.exit(1);
        };
        defer chunk.deinit();
        if (std.mem.eql(u8, mode, "run")) _ = Optimizer.optimize(&chunk);
        if (std.mem.eql(u8, mode, "bytecode") or std.mem.eql(u8, mode, "trace")) {
            var buffer: [192]u8 = undefined;
            for (chunk.code.items, 0..) |_, instruction| {
                const text = debug_mod.formatInstruction(&buffer, &chunk, instruction) catch "<invalid instruction>";
                std.debug.print("{s}\n", .{text});
            }
            if (std.mem.eql(u8, mode, "bytecode")) return;
            std.debug.print("--- execution ---\n", .{});
        }
        var vm = try Vm.init(collector.allocator());
        defer vm.deinit();
        const result = vm.run(&chunk) catch |err| {
            const location: @import("ravi_bytecode").SourceLocation = if (vm.fault_ip < chunk.source_map.items.len) chunk.source_map.items[vm.fault_ip] else .{ .start_offset = 0, .end_offset = 0, .line = 1, .column = 1 };
            printDiagnostic(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-RUNTIME-001", @errorName(err), location);
            var frame_index = vm.trace_count;
            while (frame_index > 0) {
                frame_index -= 1;
                const frame = vm.trace[frame_index];
                const frame_location: @import("ravi_bytecode").SourceLocation = if (frame.instruction < chunk.source_map.items.len) chunk.source_map.items[frame.instruction] else .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 };
                std.debug.print("  at {s} ({s}:{d}:{d})\n", .{ frame.function, managed_source.name, frame_location.line, frame_location.column });
            }
            std.process.exit(1);
        };
        if (!vm.pub_printed) std.debug.print("{d}\n", .{result});
        return;
    }
    std.debug.print("valid Ravi module: {d} syntax nodes\n", .{module.statements.items.len});
    _ = TokenKind;
    _ = Backend;
    _ = Debugger;
    _ = Scheduler;
    var syntax = try SyntaxTree.fromTokens(collector.allocator(), source, tokens);
    defer syntax.deinit();
}

fn runWithImports(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !void {
    const Context = struct { io: std.Io };
    var context = Context{ .io = io };
    const Provider = struct {
        fn read(ctx: *anyopaque, target_allocator: std.mem.Allocator, path: []const u8) anyerror![]u8 {
            const file_context: *Context = @ptrCast(@alignCast(ctx));
            return std.Io.Dir.cwd().readFileAlloc(file_context.io, path, target_allocator, .limited(16 * 1024 * 1024));
        }
    };
    var loader = ModuleLoader.init(allocator, Provider.read, @ptrCast(&context));
    defer loader.deinit();
    try loader.addSearchPath("lib");
    const order = try loader.load(root_path);
    defer allocator.free(order);
    if (order.len < 2) return error.FileNotFound;
    var combined_source = std.ArrayListUnmanaged(u8).empty;
    defer combined_source.deinit(allocator);
    var root_language = config.SourceLanguage.kn;
    for (order) |module_id| {
        const loaded = loader.module(module_id) orelse return error.InvalidModule;
        if (module_id == order[order.len - 1]) root_language = loaded.language;
        try combined_source.appendSlice(allocator, loaded.source);
        if (module_id != order[order.len - 1]) try combined_source.appendSlice(allocator, "\n");
    }
    var scan = try Lexer.initWithLanguage(allocator, combined_source.items, root_language);
    defer scan.deinit();
    const tokens = try scan.tokenize();
    var parser = Parser.initWithLanguage(allocator, tokens, root_language);
    var module = try parser.parseRecovering();
    defer module.deinit();
    if (module.diagnostics.items.len != 0) return error.InvalidModule;
    var analyzer = Analyzer.init(allocator);
    defer analyzer.deinit();
    try analyzer.analyzeWithLanguage(tokens, root_language);
    try analyzer.analyzeModule(&module);
    var chunk = try hir_pipeline.lower(allocator, &module);
    defer chunk.deinit();
    _ = Optimizer.optimize(&chunk);
    var vm = try Vm.init(allocator);
    defer vm.deinit();
    _ = try vm.run(&chunk);
}

fn printHelp() void {
    std.debug.print(
        \\Ravi programming language
        \\
        \\Usage: ravi <command> [--lang kn|en] <file.rk>
        \\
        \\Commands:
        \\  check       Parse and type-check a module
        \\  run         Compile and execute a module
        \\  trace       Disassemble, then execute a module
        \\  bytecode    Print verified bytecode with source locations
        \\  tokens      Print the token stream
        \\  fmt         Format a file in place
        \\  fmt-check   Exit nonzero when formatting differs
        \\
        \\Options:
        \\  --lang kn|en  Override the source language profile
        \\  --diagnostic-format human|compact|json
        \\  -h, --help    Show this help
        \\  -V, --version Show the compiler version
        \\
    , .{});
}

fn tokenLocation(token: @import("ravi_lexer").Token) @import("ravi_bytecode").SourceLocation {
    return .{ .start_offset = token.start_offset, .end_offset = token.end_offset, .line = token.line, .column = token.column };
}

fn printDiagnostic(allocator: std.mem.Allocator, format: DiagnosticFormat, source_name: []const u8, source: []const u8, code: []const u8, message: []const u8, location: @import("ravi_bytecode").SourceLocation) void {
    const diagnostic = diagnostics.Diagnostic{
        .code = code,
        .severity = .err,
        .message = message,
        .primary = .{
            .start_offset = location.start_offset,
            .end_offset = location.end_offset,
            .line = if (location.line == 0) 1 else location.line,
            .column = if (location.column == 0) 1 else location.column,
        },
    };
    const rendered = switch (format) {
        .human => diagnostics.renderHuman(allocator, source_name, source, diagnostic),
        .compact => diagnostics.renderCompact(allocator, source_name, diagnostic),
        .json => diagnostics.renderJson(allocator, source_name, diagnostic),
    } catch {
        std.debug.print("{s}[{s}]: {s}\n", .{ diagnostics.severityName(.err), code, message });
        return;
    };
    defer allocator.free(rendered);
    std.debug.print("{s}", .{rendered});
}
