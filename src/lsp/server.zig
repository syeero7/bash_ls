const std = @import("std");
const ts = @import("tree_sitter");
const jsonrpc = @import("jsonrpc.zig");
const types = @import("types.zig");
const Handler = @import("../Handler.zig");

// const protocol = @import("protocol.zig");
// const sync = @import("text_document_sync.zig");
// const hover = @import("../features/hover.zig");
// const definition = @import("../features/definition.zig");
// const references = @import("../features/references.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

fn isLspMethodFunc(comptime name: []const u8) bool {
    if (!std.meta.hasMethod(Handler, name)) return false;
    if (std.mem.startsWith(u8, name, "textDocument/")) return true;
    inline for ([_][]const u8{ "initialize", "initialized", "shutdown", "exit" }) |method| {
        if (std.mem.eql(u8, name, method)) return true;
    }
    return false;
}

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

// extern fn tree_sitter_bash() callconv(.c) *ts.Language;
//
// const Method = enum {
//     initialize,
//     initialized,
//     shutdown,
//     exit,
//
//     @"textDocument/didOpen",
//     @"textDocument/didChange",
//     @"textDocument/didClose",
//
//     @"textDocument/hover",
//     @"textDocument/definition",
//     @"textDocument/references",
//
//     unknown_method,
//
//     pub fn fromString(str: []const u8) @This() {
//         return std.meta.stringToEnum(@This(), str) orelse .unknown_method;
//     }
// };
//
// const State = enum {
//     not_initialized,
//     initialized,
//     shutdown,
// };

// pub fn startOld(io: Io, allocator: Allocator, reader: *Io.Reader, writer: *Io.Writer) !void {
//     _ = io;
//     const lang = tree_sitter_bash();
//     defer lang.destroy();
//
//     const parser = ts.Parser.create();
//     defer parser.destroy();
//     try parser.setLanguage(lang);
//
//     var server_state: State = .not_initialized;
//     var position_encoding: protocol.PositionEncodingKind = .@"utf-16";
//
//     var text_document = sync.TextDocumentSync.init(allocator);
//     defer text_document.deinit(allocator);
//
//     while (true) {
//         const parsed_message = protocol.parseMessage(reader, allocator) catch |err| {
//             if (err == error.EndOfStream) return err;
//             std.log.debug("message parsing failed. err: {any}", .{err});
//             try protocol.sendParseErrorResponse(writer, allocator, null);
//             continue;
//         };
//
//         defer parsed_message.deinit();
//         const message_id = parsed_message.value.id;
//         const message_params = parsed_message.value.params;
//         const message_method_string = parsed_message.value.method;
//         const message_method = Method.fromString(message_method_string);
//
//         std.log.debug("request received. method: {s}", .{message_method_string});
//         if (server_state == .not_initialized and message_method != .initialize and message_method != .initialized) {
//             try protocol.sendErrorResponse(writer, allocator, .{
//                 .id = message_id,
//                 .@"error" = .{
//                     .code = .server_not_initialized,
//                     .message = "server is not initialized",
//                 },
//             });
//             continue;
//         }
//
//         if (server_state == .shutdown and message_method != .exit) {
//             std.log.debug("invalid request received. method: {s}", .{message_method_string});
//             try protocol.sendErrorResponse(writer, allocator, .{
//                 .id = message_id,
//                 .@"error" = .{
//                     .code = .invalid_request,
//                     .message = "invalid request",
//                 },
//             });
//             continue;
//         }
//
//         switch (message_method) {
//             .initialize => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.InitializeParams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 // TODO: use initialize params
//
//                 if (parsed_params.value.capabilities.supportUtf8Encoding()) position_encoding = .@"utf-8";
//
//                 // FIXME: support utf-16 position encoding
//                 std.debug.assert(position_encoding == .@"utf-8");
//                 text_document.setPositionEncoding(position_encoding);
//
//                 const result = protocol.InitializeResult{
//                     .capabilities = .{
//                         .positionEncoding = position_encoding,
//                         .textDocumentSync = .{
//                             .openClose = true,
//                             .change = .incremental,
//                         },
//                         .hoverProvider = true,
//                         .definitionProvider = true,
//                         .referencesProvider = true,
//                     },
//                     .serverInfo = .{
//                         .name = "bash_ls",
//                         .version = "v0.0.1",
//                     },
//                 };
//
//                 try protocol.sendResultResponse(writer, allocator, protocol.InitializeResult, .{ .id = message_id.?, .result = result });
//                 continue;
//             },
//             .initialized => {
//                 std.log.debug("server initialized", .{});
//                 server_state = .initialized;
//                 continue;
//             },
//             .shutdown => {
//                 std.log.debug("shutdown request received", .{});
//                 server_state = .shutdown;
//                 try protocol.sendResultResponse(writer, allocator, struct {}, .{
//                     .id = message_id.?,
//                     .result = null,
//                 });
//                 continue;
//             },
//             .exit => {
//                 std.log.debug("exit notification received", .{});
//                 if (server_state == .shutdown) return;
//                 return error.ExitWithoutShutdown;
//             },
//             .@"textDocument/didOpen" => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.DidOpenTextDocumentParams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 try text_document.didOpen(allocator, parsed_params.value);
//             },
//             .@"textDocument/didChange" => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.DidChangeTextDocumentParams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 try text_document.didChange(allocator, parsed_params.value);
//             },
//             .@"textDocument/didClose" => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.DidCloseTextDocumentParams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 try text_document.didClose(allocator, parsed_params.value);
//             },
//             .@"textDocument/hover" => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.HoverParams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 // FIXME: should return result:null or error instead of continue
//                 const text = text_document.documents.get(parsed_params.value.textDocument.uri) orelse continue;
//                 const hover_result = try hover.hover(allocator, parser, text, parsed_params.value.position);
//                 defer if (hover_result) |result| allocator.free(result.contents.value);
//                 try protocol.sendResultResponse(writer, allocator, protocol.HoverResult, .{
//                     .id = message_id.?,
//                     .result = hover_result,
//                 });
//             },
//             .@"textDocument/definition" => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.DefinitionPrams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 // FIXME: should return result:null or error instead of continue
//                 const text = text_document.documents.get(parsed_params.value.textDocument.uri) orelse continue;
//                 const result = try definition.definition(allocator, parser, text, parsed_params.value);
//                 try protocol.sendResultResponse(writer, allocator, protocol.DefinitionResult, .{
//                     .id = message_id.?,
//                     .result = result,
//                 });
//             },
//             .@"textDocument/references" => {
//                 const parsed_params = protocol.parseParams(allocator, protocol.ReferenceParams, message_params.?) catch |err| {
//                     std.log.debug("{s} param parsing failed. err: {any}", .{ message_method_string, err });
//                     try protocol.sendParseErrorResponse(writer, allocator, message_id);
//                     continue;
//                 };
//
//                 defer parsed_params.deinit();
//                 // FIXME: should return result:null or error instead of continue
//                 const text = text_document.documents.get(parsed_params.value.textDocument.uri) orelse continue;
//                 const result = try references.references(allocator, parser, text, parsed_params.value);
//                 defer if (result) |locations| allocator.free(locations);
//                 try protocol.sendResultResponse(writer, allocator, protocol.ReferenceResult, .{
//                     .id = message_id.?,
//                     .result = result,
//                 });
//             },
//
//             else => {
//                 std.log.debug("not implemented. method: {s}", .{message_method_string});
//                 continue;
//             },
//         }
//     }
// }
