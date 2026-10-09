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

    const is_variable = std.mem.eql(u8, current_node.kind(), "variable_name");
    const is_function = std.mem.eql(u8, current_node.kind(), "word") or
        (is_variable and isBashFunction(current_node, text));
    if (!is_function and !is_variable) return null;

    const start_index = current_node.startByte();
    const end_index = current_node.endByte();
    if (start_index >= text.len or end_index > text.len) return null;

    const ranges = try findNodes(allocator, root_node, text, .{
        .kind = if (is_function) .function else .variable,
        .capture = if (params.context.includeDeclaration) .all else .exclude_first,
        .filter_text = text[start_index..end_index],
    });
    defer allocator.free(ranges);
    if (ranges.len == 0) return null;

    var locations: std.ArrayList(protocol.Location) = try .initCapacity(allocator, ranges.len);
    errdefer locations.deinit(allocator);

    for (ranges) |range| {
        try locations.append(allocator, .{
            .uri = params.textDocument.uri,
            .range = range,
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

/// check is variable_name node actually a function
fn isBashFunction(variable_node: ts.Node, document: []const u8) bool {
    const parent = variable_node.parent() orelse return false;
    if (!std.mem.eql(u8, parent.kind(), "unset_command") and
        !std.mem.eql(u8, parent.kind(), "declaration_command")) return false;

    const first_child = parent.child(0) orelse return false;
    const first_child_start = first_child.startByte();
    const first_child_end = first_child.endByte();

    if (first_child_start >= document.len or first_child_end > document.len) return false;
    const first_child_text = document[first_child_start..first_child_end];
    if (!isOptFnBuiltin(first_child_text)) return false;

    const is_declare_or_typeset = (std.mem.eql(u8, first_child.kind(), "typeset") or
        std.mem.eql(u8, first_child_text, "declare"));

    while (variable_node.prevSibling()) |sibling_node| {
        const sibling_kind = sibling_node.kind();
        if (isOptFnBuiltin(sibling_kind)) return false;
        if (!std.mem.eql(u8, sibling_kind, "word")) continue;

        const sibling_start = sibling_node.startByte();
        const sibling_end = sibling_node.endByte();
        if (sibling_start >= document.len or sibling_end > document.len) continue;

        const sibling_text = document[sibling_start..sibling_end];
        if (std.mem.eql(u8, "-f", sibling_text) or
            (is_declare_or_typeset and std.mem.eql(u8, "-F", sibling_text))) return true;
    }

    return false;
}

///  <command> [-fF] <func>
fn isOptFnBuiltin(node_text: []const u8) bool {
    inline for ([_][]const u8{ "unset", "export", "readonly", "typeset", "declare" }) |cmd| {
        if (std.mem.eql(u8, cmd, node_text)) return true;
    }

    return false;
}

const NodeKind = enum {
    function,
    variable,
};

const NodeCapture = enum {
    all,
    only_first,
    exclude_first,
};

const FindNodeOptions = struct {
    kind: NodeKind,
    capture: NodeCapture,
    filter_text: []const u8,
};

fn findNodes(
    allocator: std.mem.Allocator,
    root_node: ts.Node,
    document: []const u8,
    opt: FindNodeOptions,
) ![]protocol.Range {
    var cursor = root_node.walk();
    var should_visit_child_nodes = true;
    var found_first_match = false;
    const only_first_capture = opt.capture == .only_first;
    var items: std.ArrayList(protocol.Range) = if (only_first_capture) try .initCapacity(allocator, 1) else .empty;
    errdefer items.deinit(allocator);

    while (true) {
        find_match: {
            if (!should_visit_child_nodes) break :find_match;
            const current_node = cursor.node();
            const start_index = current_node.startByte();
            const end_index = current_node.endByte();
            if (start_index >= document.len or end_index > document.len) break :find_match;

            const node_text = document[start_index..end_index];
            if (!std.mem.eql(u8, node_text, opt.filter_text)) break :find_match;

            const node_kind = current_node.kind();

            switch (opt.kind) {
                .function => {
                    if (std.mem.eql(u8, node_kind, "word")) {
                        if (!found_first_match) {
                            found_first_match = true;
                            if (opt.capture == .exclude_first) break :find_match;
                        }

                        try items.append(allocator, tsNodeToRange(current_node));
                        if (only_first_capture) return try items.toOwnedSlice(allocator);
                    }

                    if (std.mem.eql(u8, node_kind, "variable_name")) {
                        if (!isBashFunction(current_node, document)) break :find_match;
                        try items.append(allocator, tsNodeToRange(current_node));
                    }
                },
                .variable => {
                    if (!std.mem.eql(u8, node_kind, "variable_name")) break :find_match;
                    if (!found_first_match) {
                        found_first_match = true;
                        if (opt.capture == .exclude_first) break :find_match;
                    }

                    try items.append(allocator, tsNodeToRange(current_node));
                    if (only_first_capture) return try items.toOwnedSlice(allocator);
                },
            }
        }

        if (should_visit_child_nodes and cursor.gotoFirstChild()) {
            should_visit_child_nodes = true;
            continue;
        }

        if (cursor.gotoNextSibling()) {
            should_visit_child_nodes = true;
            continue;
        }

        if (cursor.gotoParent()) {
            should_visit_child_nodes = false;
            continue;
        }

        break;
    }

    return try items.toOwnedSlice(allocator);
}

extern fn tree_sitter_bash() callconv(.c) *ts.Language;

test "find nodes" {
    const text =
        \\ VAR_1="01"
        \\ VAR_2="$VAR_1"
        \\ func_1(){ echo "ha" }
        \\ func_2(){
        \\  func_1
        \\  echo $VAR_1 || func_1
        \\ }
        \\ export VAR_1 -f func_1
        \\ unset VAR_1 -f func_1
        \\ typeset VAR_2 -f func_1 && readonly VAR_1 -f func_1
        \\ declare VAR_2 -f func_1
        \\ echo $VAR_1
        \\ func_1
    ;

    const lang = tree_sitter_bash();
    defer lang.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();

    try parser.setLanguage(lang);
    const tree = parser.parseString(text, null) orelse return error.TSParserNull;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const allocator = std.testing.allocator;
    var result = try findNodes(allocator, root_node, text, .{
        .kind = .variable,
        .capture = .all,
        .filter_text = "VAR_1",
    });
    try std.testing.expect(result.len == 7);
    allocator.free(result);

    result = try findNodes(allocator, root_node, text, .{
        .kind = .variable,
        .capture = .exclude_first,
        .filter_text = "VAR_1",
    });
    try std.testing.expect(result.len == 6);
    allocator.free(result);

    result = try findNodes(allocator, root_node, text, .{
        .kind = .variable,
        .capture = .only_first,
        .filter_text = "VAR_2",
    });
    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].start.line == 1);
    try std.testing.expect(result[0].start.character == 1);
    allocator.free(result);

    result = try findNodes(allocator, root_node, text, .{
        .kind = .function,
        .capture = .all,
        .filter_text = "func_1",
    });
    try std.testing.expect(result.len == 9);
    allocator.free(result);

    result = try findNodes(allocator, root_node, text, .{
        .kind = .function,
        .capture = .only_first,
        .filter_text = "func_2",
    });
    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].start.line == 3);
    try std.testing.expect(result[0].start.character == 1);
    allocator.free(result);

    result = try findNodes(allocator, root_node, text, .{
        .kind = .function,
        .capture = .exclude_first,
        .filter_text = "func_1",
    });
    try std.testing.expect(result.len == 8);
    allocator.free(result);
}
