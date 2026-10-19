const std = @import("std");
const ts = @import("tree_sitter");
const types = @import("types.zig");
const jsonrpc = @import("jsonrpc.zig");
const Handler = @import("../Handler.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

fn MethodResultType(comptime name: []const u8) type {
    const method_func = @field(Handler, name);
    const func_type = @typeInfo(@TypeOf(method_func));
    comptime std.debug.assert(func_type == .@"fn");
    return func_type.@"fn".return_type.?;
}

pub fn start(
    gpa: Allocator,
    arena_allocator: *std.heap.ArenaAllocator,
    handler: *Handler,
    reader: *Io.Reader,
    writer: *Io.Writer,
) !void {
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    server_loop: while (true) {
        defer _ = arena_allocator.reset(.retain_capacity);

        const parsed_message = jsonrpc.parseMessage(reader, arena) catch |err| {
            if (err == error.EndOfStream) return err;
            std.log.debug("message parsing failed. err: {any}\n", .{err});
            try jsonrpc.sendErrorResponse(writer, arena, .{ .@"error" = .{
                .code = .parse_error,
                .message = @errorName(err),
            } });
            continue;
        };

        defer parsed_message.deinit();
        const message = parsed_message.value;

        if (handler.server_state == .not_initialized and
            !std.mem.eql(u8, "initialize", message.method) and
            !std.mem.eql(u8, "initialized", message.method))
        {
            try jsonrpc.sendErrorResponse(writer, arena, .{
                .id = message.id,
                .@"error" = .{
                    .code = .server_not_initialized,
                    .message = "server is not initialized",
                },
            });
            continue;
        }

        if (handler.server_state == .shutdown and !std.mem.eql(u8, "exit", message.method)) {
            std.log.debug("invalid request received. method: {s}\n", .{message.method});
            try jsonrpc.sendErrorResponse(writer, arena, .{
                .id = message.id,
                .@"error" = .{
                    .code = .invalid_request,
                    .message = "invalid request",
                },
            });
            continue;
        }

        inline for (@typeInfo(Handler).@"struct".decls) |func| {
            if (comptime !isLspMethodFunc(func.name)) comptime continue;
            if (std.mem.eql(u8, func.name, message.method)) {
                const method_func = @field(Handler, func.name);
                const func_type = @typeInfo(@TypeOf(method_func));
                comptime std.debug.assert(func_type == .@"fn");
                const func_params = func_type.@"fn".params;
                comptime std.debug.assert(func_params.len == 4);

                const Params = comptime func_params[3].type orelse unreachable;
                var parsed_params: ?std.json.Parsed(Params) = null;
                defer if (parsed_params) |params| params.deinit();

                const params = sw: switch (@typeInfo(Params)) {
                    .@"struct" => {
                        parsed_params = jsonrpc.parseParams(arena, Params, message.params.?) catch |err| {
                            if (err == error.EndOfStream) return err;
                            std.log.debug("{s} param parsing failed. err: {any}\n", .{ message.method, err });
                            try jsonrpc.sendErrorResponse(writer, arena, .{
                                .id = message.id,
                                .@"error" = .{
                                    .code = .parse_error,
                                    .message = @errorName(err),
                                },
                            });
                            continue :server_loop;
                        };

                        break :sw parsed_params.?.value;
                    },
                    .void => break :sw {},
                    else => comptime unreachable,
                };

                const func_args = .{ handler, gpa, arena, params };
                switch (comptime @typeInfo(MethodResultType(func.name))) {
                    .void => @call(.auto, method_func, func_args),
                    .optional => {
                        if (comptime !std.mem.eql(u8, func.name, "shutdown")) comptime unreachable;
                        _ = @call(.auto, method_func, func_args);
                        try jsonrpc.sendResultResponse(writer, arena, struct {}, .{
                            .id = message.id,
                            .result = null,
                        }, .{ .emit_null_optional_fields = true });
                    },
                    .error_union => |err_union| {
                        const payload_type = comptime @typeInfo(err_union.payload);
                        switch (payload_type) {
                            .optional, .@"struct" => {
                                if (comptime payload_type == .optional) {
                                    const optional_child = comptime @typeInfo(payload_type.optional.child);
                                    if (comptime optional_child != .@"struct" and optional_child == .pointer and
                                        @typeInfo(optional_child.pointer.child) != .@"struct") comptime unreachable;
                                }

                                const result = @call(.auto, method_func, func_args) catch |err| {
                                    // TODO: send error response
                                    std.log.debug("method {s} failed. err: {any}\n", .{ func.name, err });
                                    continue :server_loop;
                                };

                                try jsonrpc.sendResultResponse(writer, arena, err_union.payload, .{
                                    .id = message.id,
                                    .result = result,
                                }, .{ .emit_null_optional_fields = false });
                            },

                            .void => {
                                @call(.auto, method_func, func_args) catch |err| {
                                    if (comptime std.mem.eql(u8, func.name, "exit")) {
                                        std.log.debug("exit with: {any}", .{err});
                                        switch (err) {
                                            error.ExitServer => return,
                                            error.ExitWithoutShutdown => return err,
                                        }
                                    }
                                    // TODO: send error response
                                    std.log.debug("method {s} failed. err: {any}\n", .{ func.name, err });
                                };
                            },
                            else => comptime unreachable,
                        }
                    },
                    else => comptime unreachable,
                }
                continue :server_loop;
            }
        }
        // TODO: err response ?
        std.log.debug("not implemented method: {s}\n", .{message.method});
    }
}

fn isLspMethodFunc(comptime name: []const u8) bool {
    if (!std.meta.hasMethod(Handler, name)) return false;
    if (std.mem.startsWith(u8, name, "textDocument/")) return true;
    inline for ([_][]const u8{ "initialize", "initialized", "shutdown", "exit" }) |method| {
        if (std.mem.eql(u8, name, method)) return true;
    }
    return false;
}
