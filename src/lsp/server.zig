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
            std.log.debug("message parsing failed. err: {any}", .{err});
            try jsonrpc.sendParseErrorResponse(writer, arena, null);
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
            std.log.debug("invalid request received. method: {s}", .{message.method});
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
            if (comptime isLspMethodFunc(func.name)) {
                if (std.mem.eql(u8, func.name, message.method)) {
                    const method_func = @field(Handler, func.name);
                    const func_type = @typeInfo(@TypeOf(method_func));
                    comptime std.debug.assert(func_type == .@"fn");

                    const func_params = func_type.@"fn".params;
                    if (comptime func_params.len == 4) {
                        const Params = comptime func_params[3].type orelse unreachable;
                        const return_type = comptime @typeInfo(MethodResultType(func.name));

                        switch (comptime @typeInfo(Params)) {
                            .@"struct" => {
                                const parsed_params = jsonrpc.parseParams(arena, Params, message.params.?) catch |err| {
                                    if (err == error.EndOfStream) return err;
                                    try jsonrpc.sendParseErrorResponse(writer, arena, null);
                                    continue :server_loop;
                                };

                                defer parsed_params.deinit();
                                if (return_type == .void) {
                                    @call(.auto, method_func, .{ handler, gpa, arena, parsed_params.value });
                                    continue :server_loop;
                                }

                                if (return_type == .error_union and return_type.error_union.payload == void) {
                                    @call(.auto, method_func, .{ handler, gpa, arena, parsed_params.value }) catch |err| {
                                        std.log.debug("method {s} failed. err: {any}", .{ func.name, err });
                                    };
                                    continue :server_loop;
                                }

                                const result = @call(.auto, method_func, .{ handler, gpa, arena, parsed_params.value }) catch |err| {
                                    std.log.debug("method {s} failed. err: {any}", .{ func.name, err });
                                    continue :server_loop;
                                };

                                try jsonrpc.sendResultResponse(writer, arena, return_type.error_union.payload, .{
                                    .id = message.id,
                                    .result = result,
                                });
                                continue :server_loop;
                            },
                            .void => {
                                if (return_type == .void) {
                                    @call(.auto, method_func, .{ handler, gpa, arena, {} });
                                    continue :server_loop;
                                }

                                if (return_type == .optional and return_type.optional.child == void) {
                                    _ = @call(.auto, method_func, .{ handler, gpa, arena, {} });
                                    try jsonrpc.sendResultResponse(writer, arena, struct {}, .{
                                        .id = message.id,
                                        .result = null,
                                    });
                                    continue :server_loop;
                                }

                                @call(.auto, method_func, .{ handler, gpa, arena, {} }) catch |err| {
                                    switch (err) {
                                        error.ExitServer => return,
                                        error.ExitWithoutShutdown => return err,
                                    }

                                    std.log.debug("method {s} failed. err: {any}", .{ func.name, err });
                                };
                                continue :server_loop;
                            },
                            else => comptime unreachable,
                        }
                    }
                }
            }
        }
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
