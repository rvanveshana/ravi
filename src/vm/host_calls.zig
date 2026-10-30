const std = @import("std");
const config = @import("ravi_config");
const Value = @import("ravi_vm_value").Value;
const Error = @import("errors.zig").RuntimeError;
const state = @import("state_helpers.zig");
const tasks = @import("tasks.zig");
const shared = @import("shared_channel.zig");
const io_runtime = @import("host_io.zig");
const storage = @import("object_storage.zig");
const collections = @import("ravi_vm_collections");

pub fn invoke(vm: anytype, operand: i64, ip: usize, next_ip: ?*usize) Error!bool {
    if (operand < 0) return error.InvalidInstruction;
    const index: usize = @intCast(@divTrunc(operand, 256));
    const count: usize = @intCast(@mod(operand, 256));
    if (index >= config.host_builtins.len or count != config.host_builtins[index].arguments or vm.stack_top < count) return error.InvalidInstruction;
    const id: config.HostBuiltin = @enumFromInt(index);
    const args = vm.stack[vm.stack_top - count .. vm.stack_top];
    var result: Value = undefined;
    if (id == .task_wait_timeout) {
        result = (try @import("task_suspension.zig").waitTimeout(vm, args, ip)) orelse {
            (next_ip orelse return error.InvalidInstruction).* = ip;
            return true;
        };
    } else if (id == .channel_send or id == .channel_recv or id == .channel_close or id == .channel_send_timeout or id == .channel_recv_timeout) {
        result = (try shared.operate(vm, id, args, ip)) orelse {
            (next_ip orelse return error.InvalidInstruction).* = ip;
            return true;
        };
    } else if (vm.cooperative and config.host_builtins[index].blocking) {
        if (vm.pending_io) |future| {
            if (!future.ready.isSet()) {
                vm.task_waiting = future;
                (next_ip orelse return error.InvalidInstruction).* = ip;
                return true;
            }
            if (vm.pending_io_ip == ip) {
                result = tasks.consume(vm, future) catch |err| {
                    future.destroy();
                    vm.pending_io = null;
                    return err;
                };
                future.destroy();
                vm.pending_io = null;
            } else {
                future.awaitReady(vm.task_scheduler.?);
                future.destroy();
                vm.pending_io = null;
                try io_runtime.start(vm, id, args, ip);
                vm.task_waiting = vm.pending_io;
                (next_ip orelse return error.InvalidInstruction).* = ip;
                return true;
            }
        } else {
            try io_runtime.start(vm, id, args, ip);
            vm.task_waiting = vm.pending_io;
            (next_ip orelse return error.InvalidInstruction).* = ip;
            return true;
        }
    } else result = try perform(vm, id, args);
    vm.stack_top -= count;
    try state.push(vm, result);
    return false;
}

fn text(vm: anytype, value: Value) Error![]const u8 {
    return vm.stringSlice(value) orelse error.TypeGuardFailed;
}
fn path(vm: anytype, value: Value) Error![]const u8 {
    const bytes = try text(vm, value);
    if (bytes.len > 32768 or std.mem.indexOfScalar(u8, bytes, 0) != null) return error.IoError;
    return bytes;
}
pub fn perform(vm: anytype, id: config.HostBuiltin, args: []const Value) Error!Value {
    switch (id) {
        .task_cancel => {
            try tasks.cancel(vm, args[0]);
            return Value.nil();
        },
        .task_release => {
            try tasks.release(vm, args[0]);
            return Value.nil();
        },
        .task_done => return Value.fromBool((try tasks.resolve(vm, args[0])).ready.isSet()),
        .channel_create => {
            if (!args[0].isInt() or args[0].asInt() <= 0) return error.TypeGuardFailed;
            const channel = try shared.Shared.create(@intCast(args[0].asInt()));
            defer channel.release();
            return shared.attach(vm, channel);
        },
        .channel_send, .channel_recv, .channel_close, .channel_send_timeout, .channel_recv_timeout => return (try shared.operate(vm, id, args, 0)).?,
        .task_wait_timeout => return (try @import("task_suspension.zig").waitTimeout(vm, args, 0)).?,
        .read_text => {
            const contents = std.Io.Dir.cwd().readFileAlloc(try io_runtime.runtime(vm), try path(vm, args[0]), vm.allocator, .limited(8 * 1024 * 1024)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.IoError;
            defer vm.allocator.free(contents);
            if (!std.unicode.utf8ValidateSlice(contents)) return error.InvalidUtf8;
            return state.internString(vm, contents);
        },
        .write_text => {
            const contents = try text(vm, args[1]);
            if (contents.len > 8 * 1024 * 1024) return error.StringTooLong;
            if (!std.unicode.utf8ValidateSlice(contents)) return error.InvalidUtf8;
            std.Io.Dir.cwd().writeFile(try io_runtime.runtime(vm), .{ .sub_path = try path(vm, args[0]), .data = contents }) catch return error.IoError;
            return Value.nil();
        },
        .path_join => {
            const joined = std.fs.path.join(vm.allocator, &.{ try path(vm, args[0]), try path(vm, args[1]) }) catch return error.OutOfMemory;
            defer vm.allocator.free(joined);
            return state.internString(vm, joined);
        },
        .path_basename => return state.internString(vm, std.fs.path.basename(try path(vm, args[0]))),
        .path_dirname => return state.internString(vm, std.fs.path.dirname(try path(vm, args[0])) orelse "."),
        .clock_mono, .clock_wall => {
            const clock: std.Io.Clock = if (id == .clock_mono) .awake else .real;
            const milliseconds = @divTrunc(std.Io.Clock.now(clock, try io_runtime.runtime(vm)).nanoseconds, std.time.ns_per_ms);
            if (milliseconds > Value.max_int or milliseconds < Value.min_int) return error.IntegerOutOfRange;
            return Value.fromInt(@intCast(milliseconds));
        },
        .json_encode => return @import("json_runtime.zig").encode(vm, args[0]),
        .json_decode => return @import("json_runtime.zig").decode(vm, try text(vm, args[0])),
        .bytes_encode => {
            const bytes = try text(vm, args[0]);
            if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
            const transaction = @import("allocation_transaction.zig").Snapshot.begin(vm);
            errdefer transaction.rollback(vm);
            const slot = try storage.newArray(vm);
            for (bytes) |byte| try collections.append(vm.arrays[slot], Value.fromInt(byte));
            return Value.fromHandle(.array, slot) catch return error.InvalidInstruction;
        },
        .bytes_decode => {
            if (args[0].handleKind() != .array and args[0].handleKind() != .tuple) return error.TypeGuardFailed;
            if (storage.objectPointer(vm, args[0]) == null) return error.InvalidInstruction;
            const array = vm.arrays[args[0].handleIndex().?];
            if (array.len > 8 * 1024 * 1024) return error.StringTooLong;
            const bytes = vm.allocator.alloc(u8, array.len) catch return error.OutOfMemory;
            defer vm.allocator.free(bytes);
            for (array.items[0..array.len], 0..) |value, i| {
                if (!value.isInt() or value.asInt() < 0 or value.asInt() > 255) return error.TypeGuardFailed;
                bytes[i] = @intCast(value.asInt());
            }
            if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
            return state.internString(vm, bytes);
        },
        .log => {
            std.debug.print("[{s}] {s}\n", .{ try text(vm, args[0]), try text(vm, args[1]) });
            return Value.nil();
        },
        .assert_equal => {
            const equal = if (args[0].handleKind() == .string and args[1].handleKind() == .string) std.mem.eql(u8, try text(vm, args[0]), try text(vm, args[1])) else Value.eql(args[0], args[1]);
            if (!equal) return error.AssertionFailed;
            return Value.nil();
        },
        .env_get => {
            const name = try text(vm, args[0]);
            const value = vm.environ.getAlloc(vm.allocator, name) catch |err| return if (err == error.EnvironmentVariableMissing) Value.nil() else if (err == error.OutOfMemory) error.OutOfMemory else error.IoError;
            defer vm.allocator.free(value);
            if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
            return state.internString(vm, value);
        },
    }
}
