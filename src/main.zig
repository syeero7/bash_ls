const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .networking = false,
    .logFn = logFn,
};

var log_file: ?std.Io.File = null;

fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime fmt: []const u8,
    args: anytype,
) void {
    _ = scope;
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [1024 * 8]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    writer.print("[bash_ls] {s}: ", .{level.asText()}) catch {};
    writer.print(fmt, args) catch {};
    writer.writeByte('\n') catch {};

    if (log_file) |file| {
        const is_locked = if (file.lock(io, .exclusive)) |_| true else |_| false;
        defer if (is_locked) file.unlock(io);
        if (file.length(io)) |length| {
            file.writePositionalAll(io, writer.buffered(), length) catch {};
        } else |_| {
            file.writeStreamingAll(io, writer.buffered()) catch {};
        }
    }
}

fn createLogFile(io: std.Io, log_file_path: []const u8) !?std.Io.File {
    const file = std.Io.Dir.cwd().createFile(io, log_file_path, .{ .truncate = false }) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => return null,
    };
    errdefer file.close(io);
    return file;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var arg_iterator = try init.minimal.args.iterateAllocator(allocator);
    while (arg_iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "--log-file")) {
            if (arg_iterator.next()) |log_file_path| {
                log_file = try createLogFile(io, log_file_path);
                arg_iterator.deinit();
                break;
            }
        }
    }

    defer if (log_file) |file| {
        file.close(io);
        log_file = null;
    };

    var lsp_initialized = false;
    var stdin_buffer: [1024 * 4]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const reader = &stdin_reader.interface;

    var stdout_buffer: [1024 * 4]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    while (true) {
        if (!lsp_initialized) {
            const parsed = jsonrpc.decode(jsonrpc.InitializeRequest, reader, allocator) catch |err| {
                std.log.debug("error: {any}", .{err});
                const res: jsonrpc.InitializeErrorResponse = .{
                    .@"error" = .{
                        .message = "failed to decode the message",
                        .data = .{
                            .retry = true,
                        },
                    },
                };
                const serialized = try jsonrpc.encode(allocator, res);
                defer allocator.free(serialized);
                try writer.writeAll(serialized);
                try writer.flush();
                continue;
            };

            defer parsed.deinit();

            if (std.mem.eql(u8, parsed.value.method, "initialize")) {
                std.log.debug("initialize request received", .{});
                const res: jsonrpc.InitializeResultResponse = .{
                    .id = parsed.value.id,
                    .result = .{
                        .serverInfo = .{
                            .name = "bash_ls",
                            .version = "v0.0.1",
                        },
                        .capabilities = .{
                            .hoverProvider = true,
                        },
                    },
                };

                const serialized = try jsonrpc.encode(allocator, res);
                defer allocator.free(serialized);
                try writer.writeAll(serialized);
                try writer.flush();
                continue;
            }

            if (std.mem.eql(u8, parsed.value.method, "initialized")) {
                lsp_initialized = true;
                std.log.debug("server initialized", .{});
                continue;
            }

            std.log.debug("server is not initialized. request method: {s}", .{parsed.value.method});
            const res: jsonrpc.NotInitializedResponse = .{
                .@"error" = .{
                    .message = "server is not initialized",
                    .data = .{
                        .retry = true,
                    },
                },
            };
            const serialized = try jsonrpc.encode(allocator, res);
            defer allocator.free(serialized);
            try writer.writeAll(serialized);
            try writer.flush();
        }
    }
}

test {
    std.testing.refAllDecls(@This());
}
