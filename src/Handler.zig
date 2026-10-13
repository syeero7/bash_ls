const std = @import("std");
const ts = @import("tree_sitter");
const types = @import("lsp/types.zig");
const offsets = @import("lib/offsets.zig");

const Allocator = std.mem.Allocator;

const Position = types.Position;
const Encoding = types.PositionEncodingKind;

const Handler = @This();

const State = enum {
    not_initialized,
    initialized,
    shutdown,
};

documents: std.StringHashMap([]u8) = undefined,
encoding: Encoding = .@"utf-16",
server_state: State = .not_initialized,
lang: *ts.Language,
parser: *ts.Parser,

pub fn initialize(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    params: types.InitializeParams,
) !types.InitializeResult {
    if (params.capabilities.supportUtf8Encoding()) self.encoding = .@"utf-8";

    // FIXME: support utf-16 position encoding
    std.debug.assert(self.encoding == .@"utf-8");

    return .{
        .capabilities = .{
            .positionEncoding = self.encoding,
            .textDocumentSync = .{
                .openClose = true,
                .change = .incremental,
            },
            .hoverProvider = true,
            .definitionProvider = true,
            .referencesProvider = true,
        },
        .serverInfo = .{
            .name = "bash_ls",
            .version = "v0.0.1",
        },
    };
}

pub fn initialized(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    _: void,
) void {
    self.server_state = .initialized;
}

pub fn shutdown(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    _: void,
) ?void {
    self.server_state = .shutdown;
    return null;
}

pub fn exit(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    _: void,
) !void {
    if (self.server_state == .shutdown) return error.ExitServer;
    return error.ExitWithoutShutdown;
}

pub fn @"textDocument/didOpen"(
    self: *@This(),
    gpa: Allocator,
    _: Allocator,
    params: types.DidOpenTextDocumentParams,
) !void {
    const text_document = params.textDocument;
    std.log.debug("file opened. uri {s}", .{text_document.uri});
    const text = try gpa.dupe(u8, text_document.text);
    errdefer gpa.free(text);

    const result = try self.documents.getOrPut(text_document.uri);
    if (result.found_existing) {
        gpa.free(result.value_ptr.*);
        result.value_ptr.* = text;
        return;
    }

    result.key_ptr.* = try gpa.dupe(u8, text_document.uri);
    result.value_ptr.* = text;
}

pub fn @"textDocument/didChange"(
    self: *@This(),
    gpa: Allocator,
    _: Allocator,
    params: types.DidChangeTextDocumentParams,
) !void {
    const current_text = self.documents.getPtr(params.textDocument.uri) orelse return;
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(gpa);
    try buffer.appendSlice(gpa, current_text.*);

    for (params.contentChanges) |change| {
        if (change.range) |range| {
            const start_index = offsets.positionToIndex(buffer.items, range.start, self.encoding);
            const relative_end = offsets.getRelativeEndPosition(range.start, range.end);
            const end_index = offsets.positionToIndex(buffer.items[start_index..], relative_end, self.encoding);
            const length = (start_index + end_index) - start_index;
            try buffer.replaceRange(gpa, start_index, length, change.text);
            continue;
        }

        // NOTE: if range is null client sent the whole document
        buffer.clearRetainingCapacity();
        try buffer.appendSlice(gpa, change.text);
    }

    const new_text = try buffer.toOwnedSlice(gpa);
    gpa.free(current_text.*);
    current_text.* = new_text;
}

pub fn @"textDocument/didClose"(
    self: *@This(),
    gpa: Allocator,
    _: Allocator,
    params: types.DidCloseTextDocumentParams,
) void {
    const entry = self.documents.fetchRemove(params.textDocument.uri) orelse return;
    gpa.free(entry.key);
    gpa.free(entry.value);
}

pub fn @"textDocument/hover"(
    self: *@This(),
    gpa: Allocator,
    arena: Allocator,
    params: types.HoverParams,
) !types.Hover {
    _ = self;
    _ = gpa;

    // TODO:
    return .{ .contents = .{
        .kind = .plaintext,
        .value = try std.fmt.allocPrint(arena, "[some thing] {s}\n other thing {s}", .{
            "stuff",
            params.textDocument.uri,
        }),
    } };
}

pub fn init(gpa: Allocator, language: *ts.Language, parser: *ts.Parser) @This() {
    return .{ .documents = .init(gpa), .lang = language, .parser = parser };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    var doc_iterator = self.documents.iterator();
    while (doc_iterator.next()) |entry| {
        gpa.free(entry.key_ptr.*);
        gpa.free(entry.value_ptr.*);
    }

    self.documents.deinit();
    self.* = undefined;
}
