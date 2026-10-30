const std = @import("std");
const Lexer = @import("ravi_lexer").Lexer;
const Parser = @import("ravi_parser").Parser;
const gc = @import("ravi_gc");
const Pipeline = @import("ravi_pipeline").Pipeline;
const Linker = @import("ravi_linker").Linker;
const ast = @import("ravi_ast");
const bytecode = @import("ravi_bytecode");
const Vm = @import("ravi_vm").Vm;
const exception_diagnostics = @import("vm/exception_diagnostics.zig");
const debug_mod = @import("ravi_debug");
const SourceManager = @import("ravi_source").Manager;
const cli_diagnostics = @import("diagnostics/cli.zig");
const formatter = @import("ravi_formatter");
const ModuleLoader = @import("ravi_loader").Loader;
const config = @import("ravi_config");
const version = "0.1.0-dev";
const sample =
    "kriya calculate(a: int, b: int):\n" ++
    "    nodu:\n" ++
    "        adre a > 10:\n" ++
    "            kodu a + b\n" ++
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
    var diagnostic_format: cli_diagnostics.DiagnosticFormat = .human;
    var profile = @import("profiling.zig").Profile{ .io = init.io };
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
            diagnostic_format = std.meta.stringToEnum(cli_diagnostics.DiagnosticFormat, name) orelse {
                std.debug.print("unknown diagnostic format: {s}\n", .{name});
                std.process.exit(2);
            };
        } else if (std.mem.eql(u8, argument, "--profile")) {
            profile.enabled = true;
        } else if (path == null) path = argument;
    }
    profile.begin();
    const loaded_source = if (path) |file_path| try std.Io.Dir.cwd().readFileAlloc(init.io, file_path, collector.allocator(), .limited(16 * 1024 * 1024)) else sample;
    profile.end(.load);
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
    profile.begin();
    var lexer = try Lexer.initWithLanguage(collector.allocator(), source, language);
    defer lexer.deinit();
    const tokens = lexer.tokenize() catch |err| {
        cli_diagnostics.print(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-LEX-001", @errorName(err), .{ .start_offset = lexer.error_offset, .end_offset = @min(lexer.error_offset + 1, source.len), .line = lexer.error_line, .column = lexer.error_column });
        std.process.exit(1);
    };
    profile.end(.lex);
    if (std.mem.eql(u8, mode, "tokens")) {
        for (tokens) |token| std.debug.print("{d}:{d} {s} {s}\n", .{ token.line, token.column, @tagName(token.kind), token.lexeme });
        return;
    }
    profile.begin();
    var parser = Parser.initWithLanguage(collector.allocator(), tokens, language);
    var module = parser.parseRecovering() catch |err| {
        const error_token = tokens[@min(parser.index, tokens.len - 1)];
        cli_diagnostics.print(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-PARSE-001", @errorName(err), cli_diagnostics.tokenLocation(error_token));
        std.process.exit(1);
    };
    defer module.deinit();
    profile.end(.parse);
    if (module.diagnostics.items.len != 0) {
        for (module.diagnostics.items) |diagnostic| {
            const token = if (diagnostic.span.first < tokens.len) tokens[diagnostic.span.first] else tokens[tokens.len - 1];
            cli_diagnostics.print(collector.allocator(), diagnostic_format, managed_source.name, source, "RAVI-PARSE-002", diagnostic.message, cli_diagnostics.tokenLocation(token));
        }
        std.process.exit(1);
    }
    const Context = struct { io: std.Io };
    var context = Context{ .io = init.io };
    const Provider = struct {
        fn read(ctx: *anyopaque, allocator: std.mem.Allocator, target: []const u8) anyerror![]u8 {
            const file_context: *Context = @ptrCast(@alignCast(ctx));
            return std.Io.Dir.cwd().readFileAlloc(file_context.io, target, allocator, .limited(16 * 1024 * 1024));
        }
    };
    var loader = ModuleLoader.init(collector.allocator(), Provider.read, @ptrCast(&context));
    defer loader.deinit();
    loader.root_language = language;
    var linker = Linker{ .allocator = collector.allocator() };
    defer linker.deinit();
    var linked: ?ast.Module = null;
    defer if (linked) |*value| value.deinit();
    if (path) |file_path| {
        profile.begin();
        try loader.addSearchPath("lib");
        const order = loader.load(file_path) catch |err| {
            const span = loader.error_span;
            cli_diagnostics.print(collector.allocator(), diagnostic_format, loader.error_path orelse file_path, loader.error_context, "RAVI-MODULE-001", @errorName(err), .{ .start_offset = span.start_offset, .end_offset = span.end_offset, .line = span.line, .column = loader.error_column });
            std.process.exit(1);
        };
        defer collector.allocator().free(order);
        for (loader.modules.items, 0..) |loaded, index| {
            if (index == 0) continue;
            _ = try source_manager.add(loaded.path, loaded.source);
        }
        linked = linker.link(&loader, order) catch |err| {
            cli_diagnostics.print(collector.allocator(), diagnostic_format, file_path, source, "RAVI-MODULE-002", @errorName(err), .{ .start_offset = 0, .end_offset = 0, .line = 1, .column = 1 });
            std.process.exit(1);
        };
        profile.end(.link);
    }
    profile.begin();
    var pipeline = Pipeline{ .allocator = collector.allocator(), .profile_io = if (profile.enabled) init.io else null };
    var chunk = pipeline.compile(if (linked) |*value| value else &module) catch |err| {
        const location = pipeline.last_location;
        const origin = source_manager.get(@enumFromInt(location.source_id)) orelse managed_source;
        cli_diagnostics.print(collector.allocator(), diagnostic_format, origin.name, origin.text, "RAVI-COMPILE-001", cli_diagnostics.compilerErrorMessage(err), location);
        std.process.exit(1);
    };
    defer chunk.deinit();
    profile.end(.compile);
    if (std.mem.eql(u8, mode, "check")) {
        std.debug.print("valid Ravi module: {d} syntax nodes\n", .{module.statements.items.len});
        return;
    }
    if (std.mem.eql(u8, mode, "run") or std.mem.eql(u8, mode, "trace") or std.mem.eql(u8, mode, "bytecode")) {
        if (std.mem.eql(u8, mode, "bytecode") or std.mem.eql(u8, mode, "trace")) {
            var buffer: [192]u8 = undefined;
            for (chunk.code.items, 0..) |_, instruction| {
                const text = debug_mod.formatInstruction(&buffer, &chunk, instruction) catch "<invalid instruction>";
                std.debug.print("{s}\n", .{text});
            }
            if (std.mem.eql(u8, mode, "bytecode")) return;
            std.debug.print("--- execution ---\n", .{});
        }
        var vm = try Vm.init(std.heap.page_allocator);
        vm.host_io = init.io;
        vm.environ = init.minimal.environ;
        vm.metrics.enabled = profile.enabled;
        vm.collector.profile_io = if (profile.enabled) init.io else null;
        defer vm.deinit();
        profile.begin();
        const result = vm.run(&chunk) catch |err| {
            const location: @import("ravi_bytecode").SourceLocation = if (vm.fault_ip < chunk.source_map.items.len) chunk.source_map.items[vm.fault_ip] else .{ .start_offset = 0, .end_offset = 0, .line = 1, .column = 1 };
            var exception_message_buffer: [256]u8 = undefined;
            const origin = source_manager.get(@enumFromInt(location.source_id)) orelse managed_source;
            cli_diagnostics.print(collector.allocator(), diagnostic_format, origin.name, origin.text, "RAVI-RUNTIME-001", exception_diagnostics.formatMessage(&exception_message_buffer, err), location);
            if (err == error.RaisedException) exception_diagnostics.printRaised(vm, vm.last_exception);
            var frame_index = vm.trace_count;
            while (frame_index > 0) {
                frame_index -= 1;
                const frame = vm.trace[frame_index];
                const frame_location: @import("ravi_bytecode").SourceLocation = if (frame.instruction < chunk.source_map.items.len) chunk.source_map.items[frame.instruction] else .{ .start_offset = 0, .end_offset = 0, .line = 0, .column = 0 };
                const frame_source = source_manager.get(@enumFromInt(frame_location.source_id)) orelse managed_source;
                std.debug.print("  at {s} ({s}:{d}:{d})\n", .{ frame.function, frame_source.name, frame_location.line, frame_location.column });
            }
            std.process.exit(1);
        };
        profile.end(.execute);
        profile.report(&vm, pipeline.timings);
        if (!vm.pub_printed) std.debug.print("{d}\n", .{result});
        return;
    }
    unreachable;
}
fn printHelp() void {
    std.debug.print(
        \\Ravi Kannada programming language
        \\
        \\Usage: ravi <command> [--lang kn|en] <file.rk>
        \\
        \\Commands:
        \\  check       Resolve, type-check, compile and verify a module
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
        \\  --profile    Report phase timings and root VM/scheduler counters
        \\  -h, --help    Show this help
        \\  -V, --version Show the compiler version
        \\
    , .{});
}
