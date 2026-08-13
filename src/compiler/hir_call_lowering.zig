const std = @import("std");
const ast = @import("ravi_ast");
const hir = @import("ravi_hir");

pub fn directArguments(allocator: std.mem.Allocator, function: *hir.Function, module: *const ast.Module, name: []const u8, call: anytype, parameters: []const []const u8, local_names: []const []const u8, capture_names: []const []const u8, line: usize, lower_argument: anytype) ![]hir.ValueId {
    var parameter_first: usize = 0;
    var parameter_count: usize = 0;
    for (module.statements.items) |statement| switch (statement.kind) {
        .function => |declaration| if (std.mem.eql(u8, declaration.name, name)) {
            parameter_first = declaration.params_first;
            parameter_count = declaration.params_count;
            break;
        },
        else => {},
    };
    const declared = module.parameters.items[parameter_first .. parameter_first + parameter_count];
    var arguments = try allocator.alloc(hir.ValueId, parameter_count);
    var filled: [64]bool = @splat(false);
    const positional_count = call.arg_count -| call.keyword_count;
    var fixed_count = parameter_count;
    var varargs_index: ?usize = null;
    var kwargs_index: ?usize = null;
    for (declared, 0..) |parameter, index| switch (parameter.kind) {
        .variadic => {
            varargs_index = index;
            fixed_count = index;
        },
        .keyword_variadic => kwargs_index = index,
        .positional => {},
    };
    if (positional_count > fixed_count and varargs_index == null) return error.InvalidFunction;
    if (positional_count < requiredParameters(declared[0..fixed_count])) return error.InvalidFunction;
    for (module.call_args.items[call.first_arg .. call.first_arg + positional_count], 0..) |argument, index| {
        if (index >= fixed_count) break;
        arguments[index] = try lower_argument(allocator, function, module, argument, parameters, local_names, capture_names);
        filled[index] = true;
    }
    var extra_values: std.ArrayListUnmanaged(hir.ValueId) = .empty;
    defer extra_values.deinit(allocator);
    if (varargs_index != null) for (module.call_args.items[call.first_arg + fixed_count .. call.first_arg + positional_count]) |argument| try extra_values.append(allocator, try lower_argument(allocator, function, module, argument, parameters, local_names, capture_names));
    if (call.keyword_count != 0) {
        if (call.keyword_first > module.call_keywords.items.len or call.keyword_count > module.call_keywords.items.len - call.keyword_first) return error.InvalidExpression;
        for (module.call_keywords.items[call.keyword_first .. call.keyword_first + call.keyword_count], module.call_args.items[call.first_arg + positional_count .. call.first_arg + call.arg_count]) |keyword, argument| {
            var matched: ?usize = null;
            for (declared[0..fixed_count], 0..) |parameter, index| {
                if (std.mem.eql(u8, parameter.name, keyword)) matched = index;
            }
            if (matched) |index| {
                if (filled[index]) return error.InvalidFunction;
                arguments[index] = try lower_argument(allocator, function, module, argument, parameters, local_names, capture_names);
                filled[index] = true;
            } else if (kwargs_index == null) return error.InvalidFunction;
        }
    }
    for (declared[0..fixed_count], 0..) |parameter, index| {
        if (!filled[index]) arguments[index] = try function.appendValue(.integer, .{ .constant_integer = parameter.default_value orelse return error.InvalidFunction }, line);
    }
    if (varargs_index) |index| arguments[index] = try function.appendValue(.dynamic, .{ .make_tuple = try extra_values.toOwnedSlice(allocator) }, line);
    if (kwargs_index) |index| {
        var values: std.ArrayListUnmanaged(hir.ValueId) = .empty;
        defer values.deinit(allocator);
        if (call.keyword_count != 0) for (module.call_keywords.items[call.keyword_first .. call.keyword_first + call.keyword_count], module.call_args.items[call.first_arg + positional_count .. call.first_arg + call.arg_count]) |keyword, argument| {
            var known = false;
            for (declared[0..fixed_count]) |parameter| {
                if (std.mem.eql(u8, parameter.name, keyword)) known = true;
            }
            if (!known) {
                try values.append(allocator, try function.appendValue(.string, .{ .constant_string = keyword }, line));
                try values.append(allocator, try lower_argument(allocator, function, module, argument, parameters, local_names, capture_names));
            }
        };
        arguments[index] = try function.appendValue(.dynamic, .{ .make_dict = try values.toOwnedSlice(allocator) }, line);
    }
    return arguments;
}

fn requiredParameters(parameters: []const ast.Parameter) usize {
    for (parameters, 0..) |parameter, index| if (parameter.default_value != null) return index;
    return parameters.len;
}
