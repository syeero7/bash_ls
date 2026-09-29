const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const protocol = @import("protocol.zig");

const Method = enum {
    initialize,
    initialized,
    shutdown,
    exit,

    unknown_method,
};

const State = enum {
    not_initialized,
    initialized,
    shutdown,
};

pub fn start(io: Io, allocator: Allocator, reader: *Io.Reader, writer: *Io.Writer) !void {
    _ = io;
    var server_state: State = .not_initialized;

    while (true) {
        const parsed_message = protocol.parseMessage(reader, allocator) catch |err| {
            if (err == error.EndOfStream) return err;
            std.log.debug("message parsing failed. err: {any}", .{err});
            try protocol.sendParseErrorResponse(writer, allocator, null);
            continue;
        };

        std.log.debug("request received. method: {s}", .{parsed_message.value.method});
        defer parsed_message.deinit();
        const message_id = parsed_message.value.id;
        const message_params = parsed_message.value.params;
        const message_method = std.meta.stringToEnum(Method, parsed_message.value.method) orelse Method.unknown_method;

        if (server_state == .not_initialized and message_method != .initialize and message_method != .initialized) {
            try protocol.sendErrorResponse(writer, allocator, .{
                .id = message_id,
                .@"error" = .{
                    .code = .server_not_initialized,
                    .message = "server is not initialized",
                },
            });
            continue;
        }

        if (server_state == .shutdown and message_method != .exit) {
            std.log.debug("invalid request received. method: {s}", .{parsed_message.value.method});
            try protocol.sendErrorResponse(writer, allocator, .{
                .id = message_id,
                .@"error" = .{
                    .code = .invalid_request,
                    .message = "invalid_request",
                },
            });
            continue;
        }

        switch (message_method) {
            .initialize => {
                const parsed_params = protocol.parseParams(allocator, protocol.InitializeParams, message_params.?) catch |err| {
                    std.log.debug("param parsing failed. err: {any}", .{err});
                    try protocol.sendParseErrorResponse(writer, allocator, null);
                    continue;
                };

                defer parsed_params.deinit();
                // TODO: use initialize params

                try protocol.sendResultResponse(writer, allocator, protocol.InitializeResult, .{
                    .id = message_id.?,
                    .result = .{
                        .serverInfo = .{
                            .name = "bash_ls",
                            .version = "v0.0.1",
                        },
                        .capabilities = .{
                            .hoverProvider = true,
                        },
                    },
                });
                continue;
            },
            .initialized => {
                std.log.debug("server initialized", .{});
                server_state = .initialized;
                continue;
            },
            .shutdown => {
                std.log.debug("shutdown request received", .{});
                server_state = .shutdown;
                try protocol.sendResultResponse(writer, allocator, struct {}, .{
                    .id = message_id.?,
                    .result = null,
                });
                continue;
            },
            .exit => {
                std.log.debug("exit notification received", .{});
                if (server_state == .shutdown) return;
                return error.ExitWithoutShutdown;
            },
            else => {
                std.log.debug("not implemented. method: {s}", .{parsed_message.value.method});
                continue;
            },
        }
    }
}
