const std = @import("std");
const server = @import("ravi_lsp_server");
const protocol = @import("ravi_lsp_protocol");
const Adapter = @import("jsonrpc.zig").Adapter;
const appendJsonString = @import("json_fields.zig").appendJsonString;

test "JSON-RPC adapter updates overlays and responds to initialize" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = try adapter.dispatch("{\"method\":\"initialize\"}");
    defer std.testing.allocator.free(response.?);
    try std.testing.expect(std.mem.indexOf(u8, response.?, "completionProvider") != null);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///a.rk\",\"text\":\"mudrisu(1)\",\"version\":1}");
    try std.testing.expectEqualStrings("mudrisu(1)", state.documentText("file:///a.rk").?);
}

test "JSON-RPC adapter preserves Content-Length framing" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    const input = try protocol.encode(std.testing.allocator, "{\"method\":\"shutdown\"}");
    defer std.testing.allocator.free(input);
    const output = (try adapter.dispatchFrame(input)).?;
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.startsWith(u8, output, "Content-Length:"));
}

test "JSON-RPC adapter serves pull diagnostics" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///bad.rk\",\"text\":\"kriya main():\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/diagnostic\",\"uri\":\"file:///bad.rk\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "items") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "RAVI-PARSE-001") != null);
}

test "JSON-RPC completion follows the opened document language" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///en.rk\",\"text\":\"# ravi: en\\nkriya main():\\n    kodu 1\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/completion\",\"uri\":\"file:///en.rk\"}")) orelse unreachable;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "function") != null);
}

test "JSON-RPC adapter serves document symbols" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///symbols.rk\",\"text\":\"kriya main():\\n    kodu 1\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/documentSymbol\",\"uri\":\"file:///symbols.rk\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "main") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"kind\":12") != null);
}

test "JSON-RPC adapter serves identifier references" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///refs.rk\",\"text\":\"kriya main():\\n    kodu main\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/references\",\"uri\":\"file:///refs.rk\",\"name\":\"main\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "file:///refs.rk") != null);
}

test "JSON-RPC adapter serves symbol definitions" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///definition.rk\",\"text\":\"kriya main():\\n    kodu main\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/definition\",\"uri\":\"file:///definition.rk\",\"name\":\"main\"}")) orelse unreachable;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"line\":0") != null);
}

test "JSON-RPC adapter serves rename edits" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///rename.rk\",\"text\":\"kriya main():\\n    kodu main\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/rename\",\"uri\":\"file:///rename.rk\",\"name\":\"main\",\"newName\":\"entry\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "entry") != null);
}

test "JSON-RPC adapter serves hover information" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    try state.open("file:///hover.rk", "kriya main():\n    kodu 1\n", 1);
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = (try adapter.dispatch("{\"method\":\"textDocument/hover\",\"uri\":\"file:///hover.rk\",\"name\":\"main\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "Function `main`") != null);
}

test "JSON-RPC adapter serves semantic tokens" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    try state.open("file:///tokens.rk", "kriya main():\n    kodu 42\n", 1);
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = (try adapter.dispatch("{\"method\":\"textDocument/semanticTokens/full\",\"uri\":\"file:///tokens.rk\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "semanticTokens") == null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"data\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "0,0,5,0,0") != null);
}

test "JSON-RPC adapter serves full document formatting edits" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    try state.open("file:///format.rk", "kriya main():  \r\n    kodu 1\t\r\n", 1);
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = (try adapter.dispatch("{\"method\":\"textDocument/formatting\",\"uri\":\"file:///format.rk\"}")).?;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "newText") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "kriya main():\\n    kodu 1\\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"line\":2") != null);
}

test "JSON-RPC adapter accepts cancellation notifications" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    try std.testing.expect((try adapter.dispatch("{\"method\":\"$/cancelRequest\",\"id\":7}")) == null);
}

test "JSON-RPC adapter serves code actions as a valid list" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    const response = (try adapter.dispatch("{\"method\":\"textDocument/codeAction\",\"uri\":\"file:///main.rk\"}")) orelse unreachable;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.endsWith(u8, response, "\"result\":[]}"));
}

test "JSON-RPC adapter returns parser quick-fix workspace edits" {
    var state = server.Server.init(std.testing.allocator);
    defer state.deinit();
    var adapter = Adapter.init(std.testing.allocator, &state);
    _ = try adapter.dispatch("{\"method\":\"textDocument/didOpen\",\"uri\":\"file:///fix.rk\",\"text\":\"kriya :\\n\",\"version\":1}");
    const response = (try adapter.dispatch("{\"method\":\"textDocument/codeAction\",\"uri\":\"file:///fix.rk\"}")) orelse unreachable;
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "quickfix") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "newText") != null);
}

test "JSON string escaping preserves control characters" {
    var encoded = std.ArrayListUnmanaged(u8).empty;
    defer encoded.deinit(std.testing.allocator);
    try appendJsonString(&encoded, std.testing.allocator, "quote\\\"line\n\t");
    try std.testing.expectEqualStrings("\"quote\\\\\\\"line\\n\\t\"", encoded.items);
}
