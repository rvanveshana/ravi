const std = @import("std");
const lexer = @import("ravi_lexer");
const parser = @import("ravi_parser");
const ast = @import("ravi_ast");
const config = @import("ravi_config");
const resolver = @import("resolver.zig");
const artifact = @import("ravi_artifact");

pub const SourceProvider = *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]u8;

pub const Module = struct {
    path: []u8,
    source: []u8,
    language: config.SourceLanguage,
    imports: std.ArrayListUnmanaged(resolver.ModuleId) = .empty,

    fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.source);
        self.imports.deinit(allocator);
    }
};

/// Loads source modules through an injected provider, parses their import
/// declarations, and builds a cycle-checked dependency graph. The provider
/// keeps this layer usable by the CLI, editor overlays, package caches, and
/// tests without coupling resolution to a filesystem implementation.
pub const Loader = struct {
    allocator: std.mem.Allocator,
    provider: SourceProvider,
    provider_context: *anyopaque,
    graph: resolver.Resolver,
    modules: std.ArrayListUnmanaged(Module) = .empty,
    search_paths: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator, provider: SourceProvider, context: *anyopaque) Loader {
        return .{ .allocator = allocator, .provider = provider, .provider_context = context, .graph = resolver.Resolver.init(allocator) };
    }

    pub fn deinit(self: *Loader) void {
        for (self.modules.items) |*entry| entry.deinit(self.allocator);
        self.modules.deinit(self.allocator);
        for (self.search_paths.items) |path| self.allocator.free(path);
        self.search_paths.deinit(self.allocator);
        self.graph.deinit();
    }

    /// Adds a package root searched after the importing file's directory.
    /// Paths are owned by the loader and consulted in insertion order.
    pub fn addSearchPath(self: *Loader, path: []const u8) !void {
        if (path.len != 0 and (path[path.len - 1] == '/' or path[path.len - 1] == '\\')) {
            try self.search_paths.append(self.allocator, try self.allocator.dupe(u8, path));
        } else {
            try self.search_paths.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}{c}", .{ path, std.fs.path.sep }));
        }
    }

    pub fn load(self: *Loader, root_path: []const u8) ![]resolver.ModuleId {
        _ = try self.visit(root_path);
        return self.graph.topologicalOrder(self.allocator);
    }

    pub fn module(self: *const Loader, id: resolver.ModuleId) ?*const Module {
        const index = @intFromEnum(id);
        if (index >= self.modules.items.len) return null;
        return &self.modules.items[index];
    }

    /// Validate and decode a cached interface without adding it to the source
    /// graph. Callers can compare the returned fingerprint with the resolver's
    /// current compiler/profile key before reusing compiled dependencies.
    pub fn decodeArtifact(self: *const Loader, bytes: []const u8, limits: artifact.Limits) !artifact.Interface {
        return artifact.decode(self.allocator, bytes, limits);
    }

    /// Checks whether a serialized interface belongs to the exact compiler,
    /// profile, and module identity requested by the current compilation.
    /// Callers can use this before loading cached declarations or bytecode;
    /// malformed, corrupted, or incompatible artifacts are never reusable.
    pub fn artifactReusable(self: *const Loader, bytes: []const u8, module_name: []const u8, compiler_key: []const u8, profile: config.SourceLanguage, limits: artifact.Limits) !bool {
        var decoded = artifact.decode(self.allocator, bytes, limits) catch |err| switch (err) {
            error.InvalidMagic, error.UnsupportedVersion, error.InvalidLength, error.ResourceLimit, error.ChecksumMismatch, error.TrailingData => return false,
            else => return err,
        };
        defer decoded.deinit();
        return std.mem.eql(u8, decoded.module_name, module_name) and
            std.mem.eql(u8, decoded.compiler_key, compiler_key) and
            decoded.profile == @intFromEnum(profile);
    }

    fn visit(self: *Loader, path: []const u8) !resolver.ModuleId {
        if (self.graph.find(path)) |existing| return existing;
        const id = try self.graph.register(path);
        const source = try self.provider(self.provider_context, self.allocator, path);
        errdefer self.allocator.free(source);
        const language = (config.languageFromHeader(source) catch |err| return err) orelse .kn;
        var scan = try lexer.Lexer.initWithLanguage(self.allocator, source, language);
        defer scan.deinit();
        const tokens = try scan.tokenize();
        var instance = parser.Parser.initWithLanguage(self.allocator, tokens, language);
        var syntax = try instance.parseRecovering();
        defer syntax.deinit();
        if (syntax.diagnostics.items.len != 0) return error.InvalidModule;
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        try self.modules.append(self.allocator, .{ .path = owned_path, .source = source, .language = language });
        // Build a concrete public interface from top-level declarations. The
        // resolver owns stable symbol names; the loader only supplies the
        // source-level declarations that are safe to import.
        for (syntax.statements.items) |statement| switch (statement.kind) {
            .function => |function| try self.graph.exportSymbol(id, function.name, resolverVisibility(function.visibility)),
            .class_decl => |class_decl| try self.graph.exportSymbol(id, class_decl.name, resolverVisibility(class_decl.visibility)),
            else => {},
        };
        for (syntax.statements.items) |statement| if (statement.kind == .import) {
            const imported = statement.kind.import.module;
            const dependency_path = try self.resolvePath(path, imported);
            const dependency = try self.visit(dependency_path);
            // Empty interfaces are retained for legacy side-effect imports.
            // Once a module declares exports, every requested symbol must be
            // present and public.
            const dependency_exports = self.graph.moduleExports(dependency);
            if (dependency_exports.len != 0) {
                for (syntax.import_names.items[statement.kind.import.names_first .. statement.kind.import.names_first + statement.kind.import.names_count]) |name| {
                    _ = self.graph.bindImport(dependency, name) catch |err| return err;
                }
            }
            try self.graph.addDependency(id, dependency);
            try self.modules.items[@intFromEnum(id)].imports.append(self.allocator, dependency);
            self.allocator.free(dependency_path);
        };
        return id;
    }

    fn resolverVisibility(visibility: ast.Visibility) resolver.Visibility {
        return switch (visibility) {
            .public => .public,
            .internal => .internal,
            .private, .protected => .private,
        };
    }

    fn resolvePath(self: *Loader, importer: []const u8, module_name: []const u8) ![]u8 {
        const separator = std.mem.lastIndexOfAny(u8, importer, "/\\");
        const directory = if (separator) |index| importer[0 .. index + 1] else "";
        const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}.rk", .{ directory, module_name });
        if (self.provider(self.provider_context, self.allocator, candidate)) |source| {
            self.allocator.free(source);
            return candidate;
        } else |_| {
            self.allocator.free(candidate);
            for (self.search_paths.items) |root| {
                const package_candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}.rk", .{ root, module_name });
                if (self.provider(self.provider_context, self.allocator, package_candidate)) |source| {
                    self.allocator.free(source);
                    return package_candidate;
                } else |_| self.allocator.free(package_candidate);
            }
            return self.allocator.dupe(u8, module_name);
        }
    }
};

test "loader parses imports, orders dependencies, and preserves profiles" {
    const Files = struct {
        fn provide(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
            const source = files.get(path) orelse return error.FileNotFound;
            return allocator.dupe(u8, source);
        }
    };
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "math inda add tago\n");
    try files.put("math.rk", "# ravi: language=en\nprint(1)\n");
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrCast(&files));
    defer loader.deinit();
    const order = try loader.load("app.rk");
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqualStrings("math.rk", loader.module(order[0]).?.path);
    try std.testing.expectEqual(config.SourceLanguage.en, loader.module(order[0]).?.language);
    try std.testing.expectEqualStrings("app.rk", loader.module(order[1]).?.path);
}

test "loader rejects import cycles" {
    const Files = struct {
        fn provide(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
            return allocator.dupe(u8, files.get(path) orelse return error.FileNotFound);
        }
    };
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("a.rk", "b inda x tago\n");
    try files.put("b.rk", "a inda x tago\n");
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrCast(&files));
    defer loader.deinit();
    try std.testing.expectError(error.ImportCycle, loader.load("a.rk"));
}

test "loader searches configured package roots after relative imports" {
    const Files = struct {
        fn provide(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
            const files: *const std.StringHashMap([]const u8) = @ptrCast(@alignCast(ctx));
            return allocator.dupe(u8, files.get(path) orelse return error.FileNotFound);
        }
    };
    var files = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer files.deinit();
    try files.put("app.rk", "math inda add tago\n");
    try files.put("pkg/math.rk", "kriya add():\n    kodu 1\n");
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrCast(&files));
    defer loader.deinit();
    try loader.addSearchPath("pkg");
    const order = try loader.load("app.rk");
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(@as(usize, 2), order.len);
    try std.testing.expectEqualStrings("pkg/math.rk", loader.module(order[0]).?.path);
}

test "loader validates cached interface artifacts" {
    const Files = struct {
        fn provide(_: *anyopaque, allocator: std.mem.Allocator, _: []const u8) ![]u8 {
            return allocator.dupe(u8, "kodu 1\n");
        }
    };
    var loader = Loader.init(std.testing.allocator, Files.provide, @ptrFromInt(1));
    defer loader.deinit();
    const bytes = try artifact.encode(std.testing.allocator, "math", "ravi-debug", 0, "exports");
    defer std.testing.allocator.free(bytes);
    var decoded = try loader.decodeArtifact(bytes, .{});
    defer decoded.deinit();
    try std.testing.expectEqualStrings("math", decoded.module_name);
    try std.testing.expectError(error.ResourceLimit, loader.decodeArtifact(bytes, .{ .max_payload_bytes = 2 }));
    try std.testing.expect(try loader.artifactReusable(bytes, "math", "ravi-debug", .kn, .{}));
    try std.testing.expect(!(try loader.artifactReusable(bytes, "math", "ravi-release", .kn, .{})));
    try std.testing.expect(!(try loader.artifactReusable(bytes, "math", "ravi-debug", .en, .{})));
    var corrupt = try std.testing.allocator.dupe(u8, bytes);
    defer std.testing.allocator.free(corrupt);
    corrupt[corrupt.len - 1] ^= 1;
    try std.testing.expect(!(try loader.artifactReusable(corrupt, "math", "ravi-debug", .kn, .{})));
}
