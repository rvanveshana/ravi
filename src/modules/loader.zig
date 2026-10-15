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
    syntax: ast.Module,
    complete: bool = false,
    imports: std.ArrayListUnmanaged(resolver.ModuleId) = .empty,

    fn deinit(self: *Module, allocator: std.mem.Allocator) void {
        self.syntax.deinit();
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
    root_language: ?config.SourceLanguage = null,
    error_path: ?[]const u8 = null,
    error_source: ?[]u8 = null,
    error_context: []const u8 = "",
    error_span: ast.Span = .{ .first = 0, .last = 0, .line = 1 },
    error_column: usize = 1,

    pub fn init(allocator: std.mem.Allocator, provider: SourceProvider, context: *anyopaque) Loader {
        return .{ .allocator = allocator, .provider = provider, .provider_context = context, .graph = resolver.Resolver.init(allocator) };
    }

    pub fn deinit(self: *Loader) void {
        if (self.error_source) |source| self.allocator.free(source);
        for (self.modules.items) |*entry| entry.deinit(self.allocator);
        self.modules.deinit(self.allocator);
        for (self.search_paths.items) |path| self.allocator.free(path);
        self.search_paths.deinit(self.allocator);
        self.graph.deinit();
    }

    /// Adds a package root searched after the importing file's directory.
    /// Paths are owned by the loader and consulted in insertion order.
    pub fn addSearchPath(self: *Loader, path: []const u8) !void {
        const owned = if (path.len != 0 and (path[path.len - 1] == '/' or path[path.len - 1] == '\\')) try self.allocator.dupe(u8, path) else try std.fmt.allocPrint(self.allocator, "{s}{c}", .{ path, std.fs.path.sep });
        errdefer self.allocator.free(owned);
        try self.search_paths.append(self.allocator, owned);
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

    fn visit(self: *Loader, path: []const u8) anyerror!resolver.ModuleId {
        const canonical = try std.fs.path.resolve(self.allocator, &.{path});
        defer self.allocator.free(canonical);
        return self.visitCanonical(canonical);
    }

    fn visitCanonical(self: *Loader, path: []const u8) anyerror!resolver.ModuleId {
        if (self.graph.find(path)) |existing| {
            const index = @intFromEnum(existing);
            if (index >= self.modules.items.len or !self.modules.items[index].complete) return error.ImportCycle;
            return existing;
        }
        const id = try self.graph.register(path);
        var published = false;
        self.error_path = self.graph.moduleName(id) catch path;
        const source = try self.provider(self.provider_context, self.allocator, path);
        errdefer if (!published) {
            self.error_source = source;
        };
        self.error_context = source;
        self.error_span = .{ .first = 0, .last = 0, .line = 1 };
        self.error_column = 1;
        const language = if (@intFromEnum(id) == 0 and self.root_language != null) self.root_language.? else (try config.languageFromHeader(source)) orelse .kn;
        var scan = try lexer.Lexer.initWithLanguage(self.allocator, source, language);
        defer scan.deinit();
        const tokens = scan.tokenize() catch |err| {
            self.error_span = .{ .first = 0, .last = 0, .line = scan.error_line, .start_offset = scan.error_offset, .end_offset = @min(scan.error_offset + 1, source.len) };
            self.error_column = scan.error_column;
            return err;
        };
        var instance = parser.Parser.initWithLanguage(self.allocator, tokens, language);
        var syntax = try instance.parseRecovering();
        errdefer if (!published) syntax.deinit();
        if (syntax.diagnostics.items.len != 0) {
            const token = tokens[@min(syntax.diagnostics.items[0].span.first, tokens.len - 1)];
            self.error_span = .{ .first = 0, .last = 0, .line = token.line, .start_offset = token.start_offset, .end_offset = token.end_offset };
            self.error_column = token.column;
            return error.InvalidModule;
        }
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer if (!published) self.allocator.free(owned_path);
        try self.modules.append(self.allocator, .{ .path = owned_path, .source = source, .language = language, .syntax = syntax });
        published = true;
        // Build a concrete public interface from top-level declarations. The
        // resolver owns stable symbol names; the loader only supplies the
        // source-level declarations that are safe to import.
        for (syntax.statements.items, 0..) |statement, statement_index| switch (statement.kind) {
            .function => |function| if (!isNested(&syntax, statement_index)) try self.graph.exportSymbol(id, function.name, resolverVisibility(function.visibility)),
            .class_decl => |class_decl| if (!isNested(&syntax, statement_index)) try self.graph.exportSymbol(id, class_decl.name, resolverVisibility(class_decl.visibility)),
            .expression => |expression| if (!isNested(&syntax, statement_index)) {
                if (syntax.expressions.items[expression].kind == .assignment) {
                    const assignment = syntax.expressions.items[expression].kind.assignment;
                    if (assignment.target == null) {
                        var present = false;
                        for (self.graph.moduleExports(id)) |symbol| if (std.mem.eql(u8, symbol.name, assignment.name)) {
                            present = true;
                            break;
                        };
                        if (!present) try self.graph.exportSymbol(id, assignment.name, .public);
                    }
                }
            },
            else => {},
        };
        for (syntax.statements.items) |statement| if (statement.kind == .import) {
            self.error_path = owned_path;
            self.error_context = source;
            self.error_span = statement.span;
            const imported = statement.kind.import.module;
            const dependency_path = try self.resolvePath(path, imported);
            defer self.allocator.free(dependency_path);
            const dependency = try self.visit(dependency_path);
            self.error_path = owned_path;
            self.error_context = source;
            self.error_span = statement.span;
            self.error_column = 1;
            for (syntax.import_names.items[statement.kind.import.names_first .. statement.kind.import.names_first + statement.kind.import.names_count]) |name| {
                _ = try self.graph.bindImport(dependency, name);
            }
            try self.graph.addDependency(id, dependency);
            try self.modules.items[@intFromEnum(id)].imports.append(self.allocator, dependency);
        };
        self.modules.items[@intFromEnum(id)].complete = true;
        return id;
    }

    fn isNested(module_ast: *const ast.Module, statement_index: usize) bool {
        for (module_ast.statements.items) |statement| switch (statement.kind) {
            .class_decl => |class_decl| if (statement_index >= class_decl.body_first and statement_index < class_decl.body_first + class_decl.body_count) return true,
            .function => |function| if (statement_index >= function.body_first and statement_index < function.body_first + function.body_count) return true,
            else => {},
        };
        return false;
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
        const relative_name = try modulePath(self.allocator, module_name);
        defer self.allocator.free(relative_name);
        const candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}.rk", .{ directory, relative_name });
        if (std.mem.eql(u8, candidate, importer)) {
            self.allocator.free(candidate);
        } else {
            if (self.provider(self.provider_context, self.allocator, candidate)) |source| {
                self.allocator.free(source);
                return candidate;
            } else |err| {
                self.allocator.free(candidate);
                if (err != error.FileNotFound) return err;
            }
        }
        for (self.search_paths.items) |root| {
            const package_candidate = try std.fmt.allocPrint(self.allocator, "{s}{s}.rk", .{ root, relative_name });
            if (self.provider(self.provider_context, self.allocator, package_candidate)) |source| {
                self.allocator.free(source);
                return package_candidate;
            } else |err| {
                self.allocator.free(package_candidate);
                if (err != error.FileNotFound) return err;
            }
        }
        return error.FileNotFound;
    }

    fn modulePath(allocator: std.mem.Allocator, module_name: []const u8) ![]u8 {
        const path = try allocator.dupe(u8, module_name);
        for (path) |*character| {
            if (character.* == '.') character.* = std.fs.path.sep;
        }
        return path;
    }
};

test {
    _ = @import("loader_tests.zig");
}
