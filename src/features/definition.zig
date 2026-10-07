const std = @import("std");
const ts = @import("tree_sitter");
const protocol = @import("../lsp/protocol.zig");

/// TODO: refactor
pub fn definition(
    allocator: std.mem.Allocator,
    parser: *ts.Parser,
    text: []const u8,
    params: protocol.DefinitionPrams,
) !?protocol.DefinitionResult {
    _ = allocator;
    const tree = parser.parseString(text, null) orelse return null;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const position = params.position;
    const point = ts.Point{ .row = position.line, .column = position.character };
    const current_node = root_node.descendantForPointRange(point, point) orelse return null;

    const start_index = current_node.startByte();
    const end_index = current_node.endByte();
    if (start_index >= text.len or end_index >= text.len) return null;

    var err_offset: u32 = 0;
    const node_text = text[start_index..end_index];
    const lang = parser.getLanguage() orelse return null;

    // FIXME: by default unset command interpret arguments as variables
    // to unset a function it needs -f option. check previous nodes.
    // unset -f <func_name>
    // what about these commands ? declare, typeset, export, readonly
    if (std.mem.eql(u8, current_node.kind(), "word")) {
        const ts_query = "(function_definition name: (word) @function)";
        const query = try ts.Query.create(lang, ts_query, &err_offset);
        defer query.destroy();

        const cursor = ts.QueryCursor.create();
        defer cursor.destroy();
        cursor.exec(query, root_node);

        const node = findNode(cursor, text, node_text) orelse return null;
        return protocol.DefinitionResult{
            .uri = params.textDocument.uri,
            .range = tsNodeToRange(node),
        };
    }

    if (std.mem.eql(u8, current_node.kind(), "variable_name")) {
        const ts_query = "(variable_assignment name: (variable_name) @variable)";
        const query = try ts.Query.create(parser.getLanguage().?, ts_query, &err_offset);
        defer query.destroy();

        const cursor = ts.QueryCursor.create();
        defer cursor.destroy();
        cursor.exec(query, root_node);

        const node = findNode(cursor, text, node_text) orelse return null;
        return protocol.DefinitionResult{
            .uri = params.textDocument.uri,
            .range = tsNodeToRange(node),
        };
    }

    return null;
}

fn findNode(cursor: *ts.QueryCursor, haystack: []const u8, needle: []const u8) ?ts.Node {
    while (cursor.nextMatch()) |match| {
        if (match.captures.len == 0) return null;
        const node = match.captures[0].node;
        const start = node.startByte();
        const end = node.endByte();

        if (start >= haystack.len or end >= haystack.len) return null;
        std.log.debug("capture: {s}\n", .{haystack[start..end]});
        if (std.mem.eql(u8, haystack[start..end], needle)) return node;
    }

    return null;
}

fn tsNodeToRange(ts_node: ts.Node) protocol.Range {
    const range = ts_node.range();
    return .{
        .start = .{
            .line = range.start_point.row,
            .character = range.start_point.column,
        },
        .end = .{
            .line = range.end_point.row,
            .character = range.end_point.column,
        },
    };
}
