const ts = @import("tree_sitter");
const types = @import("../lsp/types.zig");

extern fn tree_sitter_bash() callconv(.c) *ts.Language;

const NodeRange = struct {
    start: u32,
    end: u32,
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
