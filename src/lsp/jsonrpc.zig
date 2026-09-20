const std = @import("std");
const protocol = @import("ravi_lsp_protocol");
const server = @import("ravi_lsp_server");
const config = @import("ravi_config");

const fields = @import("json_fields.zig");
const appendJsonString = fields.appendJsonString;
const stringField = fields.stringField;
const integerField = fields.integerField;

pub const Adapter = struct {
    allocator: std.mem.Allocator,
    state: *server.Server,
    next_id: usize = 1,

    pub fn init(allocator: std.mem.Allocator, state: *server.Server) Adapter {
        return .{ .allocator = allocator, .state = state };
    }

    pub fn dispatch(self: *Adapter, body: []const u8) !?[]u8 {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch return error.InvalidRequest;
        defer parsed.deinit();
        const document = parsed.value;
        const method = stringField(document, "method") orelse return error.InvalidRequest;
        if (std.mem.eql(u8, method, "initialize")) return try self.response("{\"capabilities\":{\"completionProvider\":{},\"hoverProvider\":true,\"definitionProvider\":true,\"referencesProvider\":true,\"renameProvider\":true,\"codeActionProvider\":true,\"semanticTokensProvider\":{\"legend\":{\"tokenTypes\":[\"keyword\",\"variable\",\"number\",\"string\",\"comment\",\"operator\"],\"tokenModifiers\":[]},\"full\":true},\"diagnosticProvider\":{\"interFileDependencies\":false,\"workspaceDiagnostics\":false}}}");
        // LSP cancellation is a notification. Requests already being served
        // may finish internally, but cancellation must never tear down the
        // session or be reported as an unknown method.
        if (std.mem.eql(u8, method, "$/cancelRequest")) return null;
        if (std.mem.eql(u8, method, "shutdown")) return try self.response("null");
        if (std.mem.eql(u8, method, "exit")) return null;
        if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const text = stringField(document, "text") orelse return error.InvalidRequest;
            try self.state.open(uri, text, integerField(document, "version") orelse 1);
            return null;
        }
        if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const text = stringField(document, "text") orelse return error.InvalidRequest;
            try self.state.change(uri, text, integerField(document, "version") orelse 1);
            return null;
        }
        if (std.mem.eql(u8, method, "textDocument/didClose")) {
            self.state.close(stringField(document, "uri") orelse return error.InvalidRequest);
            return null;
        }
        if (std.mem.eql(u8, method, "textDocument/completion")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const language = self.state.documentLanguage(uri) orelse return error.UnknownMethod;
            const completions = try self.state.completions(language, self.allocator);
            defer self.allocator.free(completions);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.appendSlice(self.allocator, "{\"items\":[");
            for (completions, 0..) |completion, index| {
                if (index != 0) try result.append(self.allocator, ',');
                try result.appendSlice(self.allocator, "{\"label\":");
                try appendJsonString(&result, self.allocator, completion.label);
                try result.append(self.allocator, '}');
            }
            try result.appendSlice(self.allocator, "]}");
            return try self.response(result.items);
        }
        if (std.mem.eql(u8, method, "textDocument/diagnostic")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const diagnostics = try self.state.diagnostics(uri, self.allocator);
            defer self.allocator.free(diagnostics);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.appendSlice(self.allocator, "{\"items\":[");
            for (diagnostics, 0..) |diagnostic, index| {
                if (index != 0) try result.append(self.allocator, ',');
                var item = std.ArrayListUnmanaged(u8).empty;
                defer item.deinit(self.allocator);
                const prefix = try std.fmt.allocPrint(self.allocator, "{{\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}},\"code\":", .{ diagnostic.range.start.line, diagnostic.range.start.character, diagnostic.range.end.line, diagnostic.range.end.character });
                defer self.allocator.free(prefix);
                try item.appendSlice(self.allocator, prefix);
                try appendJsonString(&item, self.allocator, diagnostic.code);
                try item.appendSlice(self.allocator, ",\"message\":");
                try appendJsonString(&item, self.allocator, diagnostic.message);
                try item.append(self.allocator, '}');
                try result.appendSlice(self.allocator, item.items);
            }
            try result.appendSlice(self.allocator, "]}");
            return try self.response(result.items);
        }
        if (std.mem.eql(u8, method, "textDocument/codeAction")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const actions = try self.state.codeActions(uri, self.allocator);
            defer self.allocator.free(actions);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.append(self.allocator, '[');
            for (actions, 0..) |action, index| {
                if (index != 0) try result.append(self.allocator, ',');
                const fix = action.fix orelse continue;
                try result.appendSlice(self.allocator, "{\"title\":\"Insert name\",\"kind\":\"quickfix\",\"edit\":{\"changes\":{");
                try appendJsonString(&result, self.allocator, uri);
                try result.appendSlice(self.allocator, ":[{\"range\":{\"start\":{\"line\":");
                const positions = try std.fmt.allocPrint(self.allocator, "{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}},\"newText\":", .{ fix.range.start.line, fix.range.start.character, fix.range.end.line, fix.range.end.character });
                defer self.allocator.free(positions);
                try result.appendSlice(self.allocator, positions);
                try appendJsonString(&result, self.allocator, fix.replacement);
                try result.appendSlice(self.allocator, "}]}}}}");
            }
            try result.append(self.allocator, ']');
            return try self.response(result.items);
        }
        if (std.mem.eql(u8, method, "textDocument/documentSymbol")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const symbols = try self.state.documentSymbols(uri, self.allocator);
            defer self.allocator.free(symbols);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.append(self.allocator, '[');
            for (symbols, 0..) |symbol, index| {
                if (index != 0) try result.append(self.allocator, ',');
                try result.appendSlice(self.allocator, "{\"name\":");
                try appendJsonString(&result, self.allocator, symbol.name);
                const item = try std.fmt.allocPrint(self.allocator, ",\"kind\":{d},\"range\":{{\"start\":{{\"line\":{d},\"character\":0}},\"end\":{{\"line\":{d},\"character\":0}}}},\"selectionRange\":{{\"start\":{{\"line\":{d},\"character\":0}},\"end\":{{\"line\":{d},\"character\":0}}}}}}", .{ @as(u32, if (std.mem.eql(u8, symbol.kind, "Class")) 5 else 12), symbol.line, symbol.line, symbol.line, symbol.line });
                defer self.allocator.free(item);
                try result.appendSlice(self.allocator, item);
            }
            try result.append(self.allocator, ']');
            return try self.response(result.items);
        }
        if (std.mem.eql(u8, method, "textDocument/semanticTokens/full")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const tokens = try self.state.semanticTokens(uri, self.allocator);
            defer self.allocator.free(tokens);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.appendSlice(self.allocator, "{\"data\":[");
            var previous_line: u32 = 0;
            var previous_character: u32 = 0;
            for (tokens, 0..) |token, index| {
                if (index != 0) try result.append(self.allocator, ',');
                const delta_line = token.line - previous_line;
                const delta_character = if (delta_line == 0) token.character - previous_character else token.character;
                const item = try std.fmt.allocPrint(self.allocator, "{d},{d},{d},{d},0", .{ delta_line, delta_character, token.length, token.token_type });
                defer self.allocator.free(item);
                try result.appendSlice(self.allocator, item);
                previous_line = token.line;
                previous_character = token.character;
            }
            try result.appendSlice(self.allocator, "]}");
            return try self.response(result.items);
        }
        if (std.mem.eql(u8, method, "textDocument/formatting")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const original = self.state.documentText(uri) orelse return error.UnknownMethod;
            const formatted = try self.state.formatDocument(uri, self.allocator);
            defer self.allocator.free(formatted);
            var line: u32 = 0;
            for (original) |character| {
                if (character == '\n') line += 1;
            }
            var payload_list = std.ArrayListUnmanaged(u8).empty;
            defer payload_list.deinit(self.allocator);
            const prefix = try std.fmt.allocPrint(self.allocator, "[{{\"range\":{{\"start\":{{\"line\":0,\"character\":0}},\"end\":{{\"line\":{d},\"character\":0}}}},\"newText\":", .{line});
            defer self.allocator.free(prefix);
            try payload_list.appendSlice(self.allocator, prefix);
            try appendJsonString(&payload_list, self.allocator, formatted);
            try payload_list.appendSlice(self.allocator, "}}]");
            const payload = try self.allocator.dupe(u8, payload_list.items);
            defer self.allocator.free(payload);
            return try self.response(payload);
        }
        if (std.mem.eql(u8, method, "textDocument/definition")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const name = stringField(document, "name") orelse return error.InvalidRequest;
            const location = try self.state.definition(uri, name, self.allocator) orelse return try self.response("null");
            const result = try std.fmt.allocPrint(self.allocator, "{{\"uri\":", .{});
            defer self.allocator.free(result);
            var payload = std.ArrayListUnmanaged(u8).empty;
            defer payload.deinit(self.allocator);
            try payload.appendSlice(self.allocator, result);
            try appendJsonString(&payload, self.allocator, uri);
            const suffix = try std.fmt.allocPrint(self.allocator, ",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}", .{ location.line, location.character, location.line, location.character + @as(u32, @intCast(name.len)) });
            defer self.allocator.free(suffix);
            try payload.appendSlice(self.allocator, suffix);
            return try self.response(payload.items);
        }
        if (std.mem.eql(u8, method, "textDocument/references")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const name = stringField(document, "name") orelse return error.InvalidRequest;
            const references = try self.state.references(uri, name, self.allocator);
            defer self.allocator.free(references);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.append(self.allocator, '[');
            for (references, 0..) |reference, index| {
                if (index != 0) try result.append(self.allocator, ',');
                try result.appendSlice(self.allocator, "{\"uri\":");
                try appendJsonString(&result, self.allocator, uri);
                const item = try std.fmt.allocPrint(self.allocator, ",\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}}}}", .{ reference.line, reference.character, reference.line, reference.character + 1 });
                defer self.allocator.free(item);
                try result.appendSlice(self.allocator, item);
            }
            try result.append(self.allocator, ']');
            return try self.response(result.items);
        }
        if (std.mem.eql(u8, method, "textDocument/hover")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const name = stringField(document, "name") orelse return error.InvalidRequest;
            const value = try self.state.hover(uri, name, self.allocator) orelse return try self.response("null");
            defer self.allocator.free(value);
            var payload_list = std.ArrayListUnmanaged(u8).empty;
            defer payload_list.deinit(self.allocator);
            try payload_list.appendSlice(self.allocator, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
            try appendJsonString(&payload_list, self.allocator, value);
            try payload_list.appendSlice(self.allocator, "}}}");
            const payload = try self.allocator.dupe(u8, payload_list.items);
            defer self.allocator.free(payload);
            return try self.response(payload);
        }
        if (std.mem.eql(u8, method, "textDocument/rename")) {
            const uri = stringField(document, "uri") orelse return error.InvalidRequest;
            const name = stringField(document, "name") orelse return error.InvalidRequest;
            const replacement = stringField(document, "newName") orelse return error.InvalidRequest;
            const edits = try self.state.rename(uri, name, replacement, self.allocator);
            defer self.allocator.free(edits);
            var result = std.ArrayListUnmanaged(u8).empty;
            defer result.deinit(self.allocator);
            try result.appendSlice(self.allocator, "{\"changes\":{");
            try appendJsonString(&result, self.allocator, uri);
            try result.appendSlice(self.allocator, ":[");
            for (edits, 0..) |edit, index| {
                if (index != 0) try result.append(self.allocator, ',');
                const item = try std.fmt.allocPrint(self.allocator, "{{\"range\":{{\"start\":{{\"line\":{d},\"character\":{d}}},\"end\":{{\"line\":{d},\"character\":{d}}}}},\"newText\":", .{ edit.range.start.line, edit.range.start.character, edit.range.end.line, edit.range.end.character });
                defer self.allocator.free(item);
                try result.appendSlice(self.allocator, item);
                try appendJsonString(&result, self.allocator, edit.replacement);
                try result.append(self.allocator, '}');
            }
            try result.appendSlice(self.allocator, "]}}");
            return try self.response(result.items);
        }
        return error.UnknownMethod;
    }

    pub fn dispatchFrame(self: *Adapter, bytes: []const u8) !?[]u8 {
        const frame = try protocol.decode(bytes);
        const response_body = try self.dispatch(frame.body) orelse return null;
        defer self.allocator.free(response_body);
        const encoded = try protocol.encode(self.allocator, response_body);
        return @as(?[]u8, encoded);
    }

    fn response(self: *Adapter, result: []const u8) ![]u8 {
        const id = self.next_id;
        self.next_id += 1;
        return std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{s}}}", .{ id, result });
    }
};

/// Runs the JSON-RPC adapter over any Zig reader/writer pair (stdio, TCP
/// streams, or in-process test streams). Framing is incremental and supports
/// multiple requests per read as well as split headers/bodies.
pub fn serve(allocator: std.mem.Allocator, state: *server.Server, reader: anytype, writer: anytype) !void {
    var adapter = Adapter.init(allocator, state);
    var pending: std.ArrayListUnmanaged(u8) = .empty;
    defer pending.deinit(allocator);
    var input: [8192]u8 = undefined;
    while (true) {
        const count = try reader.read(&input);
        if (count == 0) return;
        try pending.appendSlice(allocator, input[0..count]);
        while (pending.items.len != 0) {
            const frame = protocol.decode(pending.items) catch |err| switch (err) {
                error.Incomplete => break,
                else => return err,
            };
            if (try adapter.dispatch(frame.body)) |response| {
                defer allocator.free(response);
                const encoded = try protocol.encode(allocator, response);
                defer allocator.free(encoded);
                try writer.writeAll(encoded);
            }
            const remaining = pending.items.len - frame.consumed;
            if (remaining == 0) {
                pending.clearRetainingCapacity();
            } else {
                std.mem.copyForwards(u8, pending.items[0..remaining], pending.items[frame.consumed..]);
                pending.shrinkRetainingCapacity(remaining);
            }
        }
    }
}

test {
    _ = @import("jsonrpc_tests.zig");
}
