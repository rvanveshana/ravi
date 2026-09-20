const std = @import("std");
const debugger = @import("ravi_debug");
const framing = @import("ravi_lsp_protocol");

pub const Adapter = struct {
    allocator: std.mem.Allocator,
    debug: *debugger.Debugger,
    next_seq: usize = 1,
    request_seq: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, debug: *debugger.Debugger) Adapter {
        return .{ .allocator = allocator, .debug = debug };
    }

    /// Dispatch one decoded DAP JSON body and return an allocated response.
    /// The adapter deliberately keeps transport framing separate so stdio,
    /// sockets, and tests can share the same command implementation.
    pub fn dispatch(self: *Adapter, body: []const u8) ![]u8 {
        self.request_seq = integerField(body, "seq") orelse 0;
        const command = stringField(body, "command") orelse return self.failure("missing command");
        if (std.mem.eql(u8, command, "initialize")) return self.success(command, "{\"supportsConfigurationDoneRequest\":true,\"supportsEvaluateForHovers\":true,\"supportsExceptionInfoRequest\":true}");
        if (std.mem.eql(u8, command, "launch") or std.mem.eql(u8, command, "configurationDone")) return self.success(command, "{}");
        if (std.mem.eql(u8, command, "pause")) {
            self.debug.requestPause();
            return self.success(command, "{}");
        }
        if (std.mem.eql(u8, command, "continue")) {
            self.debug.continueExecution();
            return self.success(command, "{\"allThreadsContinued\":true}");
        }
        if (std.mem.eql(u8, command, "next")) {
            self.debug.beginStep(.over, self.debug.frames.items.len, self.debug.step_instruction);
            return self.success(command, "{}");
        }
        if (std.mem.eql(u8, command, "stepIn")) {
            self.debug.beginStep(.into, self.debug.frames.items.len, self.debug.step_instruction);
            return self.success(command, "{}");
        }
        if (std.mem.eql(u8, command, "stepOut")) {
            self.debug.beginStep(.out, self.debug.frames.items.len, self.debug.step_instruction);
            return self.success(command, "{}");
        }
        if (std.mem.eql(u8, command, "setBreakpoints")) return self.setBreakpoints(command);
        if (std.mem.eql(u8, command, "setExceptionBreakpoints")) return self.setExceptionBreakpoints(command, body);
        if (std.mem.eql(u8, command, "threads")) return self.success(command, "{\"threads\":[{\"id\":1,\"name\":\"Ravi main\"}]}");
        if (std.mem.eql(u8, command, "stackTrace")) return self.stackTrace(command);
        if (std.mem.eql(u8, command, "scopes")) return self.scopes(command);
        if (std.mem.eql(u8, command, "variables")) return self.variables(command, body);
        if (std.mem.eql(u8, command, "evaluate")) return self.evaluate(command, body);
        if (std.mem.eql(u8, command, "disconnect") or std.mem.eql(u8, command, "terminate")) return self.success(command, "{}");
        return self.failure("unsupported command");
    }

    pub fn dispatchFrame(self: *Adapter, bytes: []const u8) ![]u8 {
        const frame = try framing.decode(bytes);
        const response = try self.dispatch(frame.body);
        defer self.allocator.free(response);
        return framing.encode(self.allocator, response);
    }

    /// Serve framed DAP messages over stdio or a connected socket stream.
    pub fn serve(self: *Adapter, reader: anytype, writer: anytype) !void {
        var pending: std.ArrayListUnmanaged(u8) = .empty;
        defer pending.deinit(self.allocator);
        var buffer: [8192]u8 = undefined;
        while (true) {
            const count = try reader.read(&buffer);
            if (count == 0) return;
            try pending.appendSlice(self.allocator, buffer[0..count]);
            while (true) {
                const frame = framing.decode(pending.items) catch |err| switch (err) {
                    error.Incomplete => break,
                    else => return err,
                };
                const response = try self.dispatch(frame.body);
                defer self.allocator.free(response);
                const encoded = try framing.encode(self.allocator, response);
                defer self.allocator.free(encoded);
                try writer.writeAll(encoded);
                const remaining = pending.items.len - frame.consumed;
                std.mem.copyForwards(u8, pending.items[0..remaining], pending.items[frame.consumed..]);
                pending.shrinkRetainingCapacity(remaining);
            }
        }
    }

    fn success(self: *Adapter, command: []const u8, body: []const u8) ![]u8 {
        const sequence = self.next_seq;
        self.next_seq += 1;
        return std.fmt.allocPrint(self.allocator, "{{\"seq\":{d},\"type\":\"response\",\"request_seq\":{d},\"success\":true,\"command\":\"{s}\",\"body\":{s}}}", .{ sequence, self.request_seq, command, body });
    }

    fn failure(self: *Adapter, message: []const u8) ![]u8 {
        const sequence = self.next_seq;
        self.next_seq += 1;
        return std.fmt.allocPrint(self.allocator, "{{\"seq\":{d},\"type\":\"response\",\"request_seq\":{d},\"success\":false,\"message\":\"{s}\"}}", .{ sequence, self.request_seq, message });
    }

    fn stackTrace(self: *Adapter, command: []const u8) ![]u8 {
        var body: std.ArrayListUnmanaged(u8) = .empty;
        defer body.deinit(self.allocator);
        try body.appendSlice(self.allocator, "{\"stackFrames\":[");
        for (self.debug.frames.items, 0..) |frame, index| {
            if (index != 0) try body.append(self.allocator, ',');
            var frame_buffer: [256]u8 = undefined;
            const instruction = if (index == 0) self.debug.paused_instruction orelse frame.instruction else frame.instruction;
            const escaped_name = try escapeJson(self.allocator, frame.function);
            defer self.allocator.free(escaped_name);
            const source = if (frame.source) |value| value else "";
            const escaped_source = try escapeJson(self.allocator, source);
            defer self.allocator.free(escaped_source);
            const frame_json = try std.fmt.bufPrint(&frame_buffer, "{{\"id\":{d},\"name\":\"{s}\",\"line\":{d},\"column\":{d},\"instruction\":{d},\"source\":{{\"name\":\"{s}\"}}}}", .{ index + 1, escaped_name, frame.line, frame.column, instruction, escaped_source });
            try body.appendSlice(self.allocator, frame_json);
        }
        try body.appendSlice(self.allocator, "]}");
        return self.success(command, body.items);
    }

    fn setBreakpoints(self: *Adapter, command: []const u8) ![]u8 {
        var body: std.ArrayListUnmanaged(u8) = .empty;
        defer body.deinit(self.allocator);
        try body.appendSlice(self.allocator, "{\"breakpoints\":[");
        for (self.debug.breakpoints.items, 0..) |point, index| {
            if (index != 0) try body.append(self.allocator, ',');
            const item = try std.fmt.allocPrint(self.allocator, "{{\"id\":{d},\"verified\":{s},\"instruction\":{d}}}", .{ point.id, if (point.enabled) "true" else "false", point.instruction });
            defer self.allocator.free(item);
            try body.appendSlice(self.allocator, item);
        }
        try body.appendSlice(self.allocator, "]}");
        return self.success(command, body.items);
    }

    fn scopes(self: *Adapter, command: []const u8) ![]u8 {
        var body: std.ArrayListUnmanaged(u8) = .empty;
        defer body.deinit(self.allocator);
        try body.appendSlice(self.allocator, "{\"scopes\":[");
        for (self.debug.scopes.items, 0..) |scope, index| {
            if (index != 0) try body.append(self.allocator, ',');
            const name = try escapeJson(self.allocator, scope.name);
            defer self.allocator.free(name);
            const scope_json = try std.fmt.allocPrint(self.allocator, "{{\"name\":\"{s}\",\"presentationHint\":\"locals\",\"variablesReference\":{d},\"expensive\":false}}", .{ name, index + 1 });
            defer self.allocator.free(scope_json);
            try body.appendSlice(self.allocator, scope_json);
        }
        try body.appendSlice(self.allocator, "]}");
        return self.success(command, body.items);
    }

    fn variables(self: *Adapter, command: []const u8, request_body: []const u8) ![]u8 {
        const reference = integerField(request_body, "variablesReference") orelse 0;
        var body: std.ArrayListUnmanaged(u8) = .empty;
        defer body.deinit(self.allocator);
        try body.appendSlice(self.allocator, "{\"variables\":[");
        if (reference > 0 and @as(usize, @intCast(reference)) <= self.debug.scopes.items.len) {
            const scope = self.debug.scopes.items[@intCast(reference - 1)];
            for (scope.variables, 0..) |variable, index| {
                if (index != 0) try body.append(self.allocator, ',');
                const name = try escapeJson(self.allocator, variable.name);
                defer self.allocator.free(name);
                const variable_json = try std.fmt.allocPrint(self.allocator, "{{\"name\":\"{s}\",\"value\":\"{d}\",\"type\":\"int\",\"variablesReference\":0}}", .{ name, variable.value });
                defer self.allocator.free(variable_json);
                try body.appendSlice(self.allocator, variable_json);
            }
        }
        try body.appendSlice(self.allocator, "]}");
        return self.success(command, body.items);
    }

    fn evaluate(self: *Adapter, command: []const u8, body: []const u8) ![]u8 {
        const expression = stringField(body, "expression") orelse return self.failure("missing expression");
        const value = debugger.Debugger.evaluate(self.debug.scopes.items, expression) catch return self.failure("unknown variable");
        const result = try std.fmt.allocPrint(self.allocator, "{{\"result\":\"{d}\",\"type\":\"int\",\"variablesReference\":0}}", .{value});
        defer self.allocator.free(result);
        return self.success(command, result);
    }

    fn setExceptionBreakpoints(self: *Adapter, command: []const u8, body: []const u8) ![]u8 {
        const all = std.mem.indexOf(u8, body, "all") != null;
        self.debug.setExceptionBreakpoints(all, all);
        return self.success(command, "{\"breakpoints\":[]}");
    }
};

fn escapeJson(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var result = std.ArrayListUnmanaged(u8).empty;
    errdefer result.deinit(allocator);
    for (value) |character| switch (character) {
        '"' => try result.appendSlice(allocator, "\\\""),
        '\\' => try result.appendSlice(allocator, "\\\\"),
        '\n' => try result.appendSlice(allocator, "\\n"),
        '\r' => try result.appendSlice(allocator, "\\r"),
        '\t' => try result.appendSlice(allocator, "\\t"),
        else => try result.append(allocator, character),
    };
    return result.toOwnedSlice(allocator);
}

fn stringField(body: []const u8, field: []const u8) ?[]const u8 {
    var key: [96]u8 = undefined;
    const key_text = std.fmt.bufPrint(&key, "\"{s}\":\"", .{field}) catch return null;
    const start = (std.mem.indexOf(u8, body, key_text) orelse return null) + key_text.len;
    const end = std.mem.indexOfScalarPos(u8, body, start, '"') orelse return null;
    return body[start..end];
}

fn integerField(body: []const u8, field: []const u8) ?i64 {
    var key: [96]u8 = undefined;
    const key_text = std.fmt.bufPrint(&key, "\"{s}\":", .{field}) catch return null;
    const start = (std.mem.indexOf(u8, body, key_text) orelse return null) + key_text.len;
    var end = start;
    while (end < body.len and (body[end] == '-' or (body[end] >= '0' and body[end] <= '9'))) : (end += 1) {}
    if (end == start) return null;
    return std.fmt.parseInt(i64, body[start..end], 10) catch null;
}

test "DAP adapter dispatches lifecycle, stepping, and stack frames" {
    var state = debugger.Debugger.init(std.testing.allocator);
    defer state.deinit();
    try state.updateFrames(&.{.{ .function = "main", .instruction = 4, .line = 9 }});
    state.paused_instruction = 7;
    var adapter = Adapter.init(std.testing.allocator, &state);
    const initialized = try adapter.dispatch("{\"command\":\"initialize\"}");
    defer std.testing.allocator.free(initialized);
    try std.testing.expect(std.mem.indexOf(u8, initialized, "supportsEvaluateForHovers") != null);
    const trace = try adapter.dispatch("{\"command\":\"stackTrace\"}");
    defer std.testing.allocator.free(trace);
    try std.testing.expect(std.mem.indexOf(u8, trace, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, trace, "\"instruction\":7") != null);
    const paused = try adapter.dispatch("{\"command\":\"pause\"}");
    defer std.testing.allocator.free(paused);
    try std.testing.expect(state.paused);
}

test "DAP adapter exposes a stable Ravi thread view" {
    var state = debugger.Debugger.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = try adapter.dispatch("{\"seq\":3,\"command\":\"threads\"}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "Ravi main") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"id\":1") != null);
}

test "DAP responses preserve request sequence numbers" {
    var state = debugger.Debugger.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = try adapter.dispatch("{\"seq\":42,\"command\":\"pause\"}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"request_seq\":42") != null);
}

test "DAP adapter uses LSP-compatible content framing" {
    var state = debugger.Debugger.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    const input = try framing.encode(std.testing.allocator, "{\"command\":\"continue\"}");
    defer std.testing.allocator.free(input);
    const framed = try adapter.dispatchFrame(input);
    defer std.testing.allocator.free(framed);
    try std.testing.expect(std.mem.startsWith(u8, framed, "Content-Length:"));
    try std.testing.expect(std.mem.indexOf(u8, framed, "\"success\":true") != null);
}

test "DAP stack frames escape user function names" {
    var state = debugger.Debugger.init(std.testing.allocator);
    defer state.deinit();
    try state.updateFrames(&.{.{ .function = "main\"quoted", .instruction = 1, .line = 1 }});
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = try adapter.dispatch("{\"command\":\"stackTrace\"}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "main\\\"quoted") != null);
}

test "DAP breakpoint response reflects debugger state" {
    var state = debugger.Debugger.init(std.testing.allocator);
    defer state.deinit();
    _ = try state.addBreakpoint(12);
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = try adapter.dispatch("{\"command\":\"setBreakpoints\"}");
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"id\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"instruction\":12") != null);
}
