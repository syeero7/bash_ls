const std = @import("std");
const ts = @import("tree_sitter");
const types = @import("../lsp/types.zig");

const mem = std.mem;
const testing = std.testing;

extern fn tree_sitter_bash() callconv(.c) *ts.Language;

const NodeRange = struct {
    start: u32,
    end: u32,
};

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
    node_text: []const u8,
};

pub fn getLang() *ts.Language {
    return tree_sitter_bash();
}

pub fn getCurrentNode(root_node: ts.Node, position: types.Position) ?ts.Node {
    const point = ts.Point{ .row = position.line, .column = position.character };
    return root_node.descendantForPointRange(point, point);
}

pub fn getNodeRange(node: ts.Node, document_length: usize) ?NodeRange {
    const range = node.range();
    if (range.start_byte >= document_length or range.end_byte > document_length) return null;
    return .{ .start = range.start_byte, .end = range.end_byte };
}

pub fn isFunction(node_kind: []const u8) bool {
    return mem.eql(u8, node_kind, "word");
}

/// return true if function identified as word or variable_name
pub fn isFunctionForReal(node: ts.Node, document: []const u8) bool {
    const node_kind = node.kind();
    if (isFunction(node_kind)) return true;
    if (!isVariable(node_kind)) return false;

    const parent_node = node.parent() orelse return false;
    const command_node = parent_node.child(0) orelse return false;
    const command_range = getNodeRange(command_node, document.len) orelse return false;
    const command_text = document[command_range.start..command_range.end];
    if (!isBuiltinTakesFunc(command_text)) return false;

    const is_declare_or_typeset = (mem.eql(u8, command_text, "typeset") or
        mem.eql(u8, command_text, "declare"));

    while (node.prevSibling()) |sibling_node| {
        const sibling_kind = sibling_node.kind();
        if (isBuiltinTakesFunc(sibling_kind)) return false;
        // NOTE: -f and -F  nodes identified as word
        if (!isFunction(sibling_kind)) continue;

        const sibling_range = getNodeRange(sibling_node, document.len) orelse return false;
        const sibling_text = document[sibling_range.start..sibling_range.end];
        if (mem.eql(u8, "-f", sibling_text)) return true;
        if ((is_declare_or_typeset and mem.eql(u8, "-F", sibling_text))) return true;
    }

    return false;
}

pub fn isVariable(node_kind: []const u8) bool {
    return mem.eql(u8, node_kind, "variable_name");
}

pub fn isString(node_kind: []const u8) bool {
    inline for ([_][]const u8{
        "string",        "raw_string",     "heredoc_body",
        "heredoc_start", "string_content",
    }) |string_kind| {
        if (mem.eql(u8, string_kind, node_kind)) return true;
    }
    return false;
}

pub fn isFunctionDefinition(node_kind: []const u8) bool {
    return mem.eql(u8, node_kind, "function_definition");
}

pub fn getFunctionDefinitionText(
    allocator: mem.Allocator,
    root_node: ts.Node,
    document: []const u8,
    node_text: []const u8,
) !?[]const u8 {
    const locations = try getMatchingNodeRanges(allocator, root_node, document, .{
        .kind = .function,
        .capture = .only_first,
        .node_text = node_text,
    });

    if (locations.len == 0) return null;
    const current_node = getCurrentNode(root_node, locations[0].start) orelse return null;
    if (current_node.parent()) |parent_node| {
        if (!isFunctionDefinition(parent_node.kind())) return null;
        const node_range = getNodeRange(parent_node, document.len) orelse return null;
        return document[node_range.start..node_range.end];
    }

    return null;
}

// source: https://www.gnu.org/software/bash/manual/bash.html#Reserved-Words-1
pub fn isReservedWord(node_text: []const u8) bool {
    inline for ([_][]const u8{
        "if",   "then", "elif",   "else",   "fi",       "time",
        "for",  "in",   "until",  "while",  "do",       "done",
        "case", "esac", "coproc", "select", "function", "{",
        "}",    "[[",   "]]",     "!",
    }) |word| {
        if (std.mem.eql(u8, word, node_text)) return true;
    }

    return false;
}

pub fn getMatchingNodeRanges(
    allocator: mem.Allocator,
    root_node: ts.Node,
    document: []const u8,
    opt: FindNodeOptions,
) ![]types.Range {
    var cursor = root_node.walk();
    var should_visit_child_nodes = true;
    var found_first_match = false;

    const only_first_capture = opt.capture == .only_first;
    var ranges: std.ArrayList(types.Range) = if (only_first_capture) try .initCapacity(allocator, 1) else .empty;
    errdefer ranges.deinit(allocator);

    while (true) {
        if (should_visit_child_nodes) {
            found_match: {
                const current_node = cursor.node();
                if (!isNodeMatch(current_node, document, opt)) break :found_match;
                if (!found_first_match) {
                    found_first_match = true;
                    if (opt.capture == .exclude_first) break :found_match;
                }

                try ranges.append(allocator, toLspRange(current_node.range()));
                if (only_first_capture) return try ranges.toOwnedSlice(allocator);
            }

            if (cursor.gotoFirstChild()) {
                should_visit_child_nodes = true;
                continue;
            }
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

    return try ranges.toOwnedSlice(allocator);
}

///  <command> [-fF] <func>
fn isBuiltinTakesFunc(command_text: []const u8) bool {
    inline for ([_][]const u8{ "unset", "export", "readonly", "typeset", "declare" }) |cmd| {
        if (mem.eql(u8, cmd, command_text)) return true;
    }

    return false;
}

fn isNodeMatch(node: ts.Node, document: []const u8, options: FindNodeOptions) bool {
    const node_range = getNodeRange(node, document.len) orelse return false;
    const node_text = document[node_range.start..node_range.end];
    if (!mem.eql(u8, options.node_text, node_text)) return false;

    return switch (options.kind) {
        .function => isFunctionForReal(node, document),
        .variable => isVariable(node.kind()),
    };
}

fn toLspRange(range: ts.Range) types.Range {
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

test "find matching node ranges" {
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

    const lang = getLang();
    defer lang.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();

    try parser.setLanguage(lang);
    const tree = parser.parseString(text, null) orelse return error.TSParserNull;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const allocator = testing.allocator;
    var result = try getMatchingNodeRanges(allocator, root_node, text, .{
        .kind = .variable,
        .capture = .all,
        .node_text = "VAR_1",
    });
    try testing.expect(result.len == 7);
    allocator.free(result);

    result = try getMatchingNodeRanges(allocator, root_node, text, .{
        .kind = .variable,
        .capture = .exclude_first,
        .node_text = "VAR_1",
    });
    try testing.expect(result.len == 6);
    allocator.free(result);

    result = try getMatchingNodeRanges(allocator, root_node, text, .{
        .kind = .variable,
        .capture = .only_first,
        .node_text = "VAR_2",
    });
    try testing.expect(result.len == 1);
    try testing.expect(result[0].start.line == 1);
    try testing.expect(result[0].start.character == 1);
    allocator.free(result);

    result = try getMatchingNodeRanges(allocator, root_node, text, .{
        .kind = .function,
        .capture = .all,
        .node_text = "func_1",
    });
    try testing.expect(result.len == 9);
    allocator.free(result);

    result = try getMatchingNodeRanges(allocator, root_node, text, .{
        .kind = .function,
        .capture = .only_first,
        .node_text = "func_2",
    });
    try testing.expect(result.len == 1);
    try testing.expect(result[0].start.line == 3);
    try testing.expect(result[0].start.character == 1);
    allocator.free(result);

    result = try getMatchingNodeRanges(allocator, root_node, text, .{
        .kind = .function,
        .capture = .exclude_first,
        .node_text = "func_1",
    });
    try testing.expect(result.len == 8);
    allocator.free(result);
}
