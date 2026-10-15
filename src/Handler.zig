const std = @import("std");
const ts = @import("tree_sitter");
const types = @import("lsp/types.zig");
const offsets = @import("lib/offsets.zig");
const ts_bash = @import("lib/tree_sitter_bash.zig");

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

pub fn @"textDocument/definition"(
    self: *@This(),
    _: Allocator,
    arena: Allocator,
    params: types.DefinitionPrams,
) !?types.DefinitionResult {
    const document_uri = params.textDocument.uri;
    const document = self.documents.get(document_uri) orelse return null;
    const tree = self.parser.parseString(document, null) orelse return null;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const current_node = ts_bash.getCurrentNode(root_node, params.position) orelse return null;
    const is_function = ts_bash.isFunctionForReal(current_node, document);
    if (!is_function and !ts_bash.isVariable(current_node.kind())) return null;

    const node_range = ts_bash.getNodeRange(current_node, document.len) orelse return null;
    const ranges = try ts_bash.getMatchingNodeRanges(arena, root_node, document, .{
        .kind = if (is_function) .function else .variable,
        .capture = .only_first,
        .node_text = document[node_range.start..node_range.end],
    });

    if (ranges.len == 0) return null;
    return .{ .uri = document_uri, .range = ranges[0] };
}

pub fn @"textDocument/references"(
    self: *@This(),
    _: Allocator,
    arena: Allocator,
    params: types.ReferenceParams,
) !?types.ReferenceResult {
    const document_uri = params.textDocument.uri;
    const document = self.documents.get(document_uri) orelse return null;
    const tree = self.parser.parseString(document, null) orelse return null;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const current_node = ts_bash.getCurrentNode(root_node, params.position) orelse return null;
    const is_function = ts_bash.isFunctionForReal(current_node, document);
    if (!is_function and !ts_bash.isVariable(current_node.kind())) return null;

    const node_range = ts_bash.getNodeRange(current_node, document.len) orelse return null;
    const ranges = try ts_bash.getMatchingNodeRanges(arena, root_node, document, .{
        .kind = if (is_function) .function else .variable,
        .capture = if (params.context.includeDeclaration) .all else .exclude_first,
        .node_text = document[node_range.start..node_range.end],
    });

    if (ranges.len == 0) return null;
    var locations: std.ArrayList(types.Location) = try .initCapacity(arena, ranges.len);
    errdefer locations.deinit(arena);

    for (ranges) |range| {
        try locations.append(arena, .{
            .uri = document_uri,
            .range = range,
        });
    }

    return try locations.toOwnedSlice(arena);
}

pub fn @"textDocument/hover"(
    self: *@This(),
    _: Allocator,
    arena: Allocator,
    params: types.HoverParams,
) !?types.Hover {
    const document = self.documents.get(params.textDocument.uri) orelse return null;
    const tree = self.parser.parseString(document, null) orelse return null;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const current_node = ts_bash.getCurrentNode(root_node, params.position) orelse return null;
    const node_range = ts_bash.getNodeRange(current_node, document.len) orelse return null;
    const node_text = document[node_range.start..node_range.end];
    if (ts_bash.isReservedWord(node_text)) return null;
    var hover: types.Hover = .{ .contents = .{ .kind = .markdown, .value = undefined } };

    if (ts_bash.isFunctionForReal(current_node, document)) {
        hover.contents.value = try std.fmt.allocPrint(arena, "```bash\n{s}\n```", .{
            try ts_bash.getFunctionDefinitionText(arena, root_node, document, node_text) orelse return null,
        });
        return hover;
    }

    const node_kind = current_node.kind();
    // TODO: for variables show recently assigned value

    hover.contents.value = try std.fmt.allocPrint(arena, "**{s}**\n```bash\n{s}\n```", .{
        node_kind,
        node_text,
    });
    return hover;
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
