const std = @import("std");
const ts = @import("tree_sitter");
const protocol = @import("../lsp/protocol.zig");

pub fn references(
    allocator: std.mem.Allocator,
    parser: *ts.Parser,
    text: []const u8,
    params: protocol.ReferenceParams,
) !?protocol.ReferenceResult {
    const tree = parser.parseString(text, null) orelse return null;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const position = params.position;
    const point = ts.Point{ .row = position.line, .column = position.character };
    const current_node = root_node.descendantForPointRange(point, point) orelse return null;

    const is_function = std.mem.eql(u8, current_node.kind(), "word");
    const is_variable = std.mem.eql(u8, current_node.kind(), "variable_name");
    if (!is_function and !is_variable) return null;

    const start_index = current_node.startByte();
    const end_index = current_node.endByte();
    if (start_index >= text.len or end_index >= text.len) return null;

    const node_text = text[start_index..end_index];
    const lang = root_node.getLanguage();
    var err_offset: u32 = 0;
    var query: *ts.Query = undefined;

    if (is_function) {
        // FIXME: by default unset command interpret arguments as variables
        // to unset a function it needs -f option. check previous nodes.
        // unset -f <func_name>
        // unset VAR_1 VAR_2 -f func_1 func_2
        const ts_query = "((word) @function)";
        query = try ts.Query.create(lang, ts_query, &err_offset);
    }

    if (is_variable) {
        const ts_query = "((variable_name) @variable)";
        query = try ts.Query.create(lang, ts_query, &err_offset);
    }

    defer query.destroy();
    const cursor = ts.QueryCursor.create();
    defer cursor.destroy();
    cursor.exec(query, root_node);

    var locations: std.ArrayList(protocol.Location) = .empty;
    errdefer locations.deinit(allocator);

    var is_first_capture = true;
    while (cursor.nextMatch()) |match| {
        if (match.captures.len == 0) continue;
        const node = match.captures[0].node;
        const start = node.startByte();
        const end = node.endByte();

        if (start >= text.len or end >= text.len) continue;
        if (!std.mem.eql(u8, text[start..end], node_text)) continue;
        std.log.debug("text: {s} kind: {s}\n", .{ text[start..end], node.kind() });
        if (!params.context.includeDeclaration and is_first_capture) {
            is_first_capture = false;
            continue;
        }

        try locations.append(allocator, .{
            .uri = params.textDocument.uri,
            .range = tsNodeToRange(node),
        });
    }

    return try locations.toOwnedSlice(allocator);
}

// NOTE: duplicate function
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
