const std = @import("std");
const protocol = @import("protocol.zig");
const sync = @import("document_sync.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Method = enum {
    initialize,
    initialized,
    shutdown,
    exit,

    @"textDocument/didOpen",
    @"textDocument/didChange",
    @"textDocument/didClose",

    unknown_method,

    pub fn fromString(str: []const u8) @This() {
        return std.meta.stringToEnum(@This(), str) orelse .unknown_method;
    }
};

const State = enum {
    not_initialized,
    initialized,
    shutdown,
};

pub fn start(io: Io, allocator: Allocator, reader: *Io.Reader, writer: *Io.Writer) !void {
    _ = io;
    var server_state: State = .not_initialized;
    var position_encoding: protocol.PositionEncodingKind = .@"utf-16";
    var document_sync = sync.DocumentSync.init(allocator);
    defer document_sync.deinit(allocator);

    while (true) {
        const parsed_message = protocol.parseMessage(reader, allocator) catch |err| {
            if (err == error.EndOfStream) return err;
            std.log.debug("message parsing failed. err: {any}", .{err});
            try protocol.sendParseErrorResponse(writer, allocator, null);
            continue;
        };

        defer parsed_message.deinit();
        const message_id = parsed_message.value.id;
        const message_params = parsed_message.value.params;
        const message_method_string = parsed_message.value.method;
        const message_method = Method.fromString(message_method_string);

        std.log.debug("request received. method: {s}", .{message_method_string});
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
            std.log.debug("invalid request received. method: {s}", .{message_method_string});
            try protocol.sendErrorResponse(writer, allocator, .{
                .id = message_id,
                .@"error" = .{
                    .code = .invalid_request,
                    .message = "invalid request",
                },
            });
            continue;
        }

        switch (message_method) {
            .initialize => {
                const parsed_params = protocol.parseParams(allocator, protocol.InitializeParams, message_params.?) catch |err| {
                    std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
                    try protocol.sendParseErrorResponse(writer, allocator, message_id);
                    continue;
                };

                defer parsed_params.deinit();
                // TODO: use initialize params

                if (parsed_params.value.capabilities.supportUtf8Encoding()) position_encoding = .@"utf-8";

                // FIXME: support utf-16 position encoding
                std.debug.assert(position_encoding == .@"utf-8");
                document_sync.setPositionEncoding(position_encoding);

                const result = protocol.InitializeResult{
                    .capabilities = .{
                        .positionEncoding = position_encoding,
                        .textDocumentSync = .{
                            .openClose = true,
                            .change = .incremental,
                        },
                        .hoverProvider = true,
                    },
                    .serverInfo = .{
                        .name = "bash_ls",
                        .version = "v0.0.1",
                    },
                };

                try protocol.sendResultResponse(writer, allocator, protocol.InitializeResult, .{ .id = message_id.?, .result = result });
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
            .@"textDocument/didOpen" => {
                const parsed_params = protocol.parseParams(allocator, protocol.DidOpenTextDocumentParams, message_params.?) catch |err| {
                    std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
                    try protocol.sendParseErrorResponse(writer, allocator, message_id);
                    continue;
                };

                defer parsed_params.deinit();
                try document_sync.didOpen(allocator, parsed_params.value);
            },
            .@"textDocument/didChange" => {
                const parsed_params = protocol.parseParams(allocator, protocol.DidChangeTextDocumentParams, message_params.?) catch |err| {
                    std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
                    try protocol.sendParseErrorResponse(writer, allocator, message_id);
                    continue;
                };

                defer parsed_params.deinit();
                try document_sync.didChange(allocator, parsed_params.value);
            },
            .@"textDocument/didClose" => {},

            else => {
                std.log.debug("not implemented. method: {s}", .{message_method_string});
                continue;
            },
        }
    }
}
