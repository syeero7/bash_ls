const std = @import("std");
const ts = @import("tree_sitter");
const protocol = @import("../lsp/protocol.zig");

/// TODO: include more info in hover content.
pub fn hover(
    allocator: std.mem.Allocator,
    parser: *ts.Parser,
    text: []const u8,
    position: protocol.Position,
) !?protocol.HoverResult {
    const tree = parser.parseString(text, null) orelse return null;
    defer tree.destroy();

    const root_node = tree.rootNode();
    const point = ts.Point{ .row = position.line, .column = position.character };
    const node = root_node.descendantForPointRange(point, point) orelse return null;

    const start_index = node.startByte();
    const end_index = node.endByte();
    if (start_index >= text.len or end_index >= text.len) return null;

    return protocol.HoverResult{
        .contents = .{
            .kind = .markdown,
            .value = try std.fmt.allocPrint(allocator, "```bash\n{s} {s}\n```", .{ node.kind(), text[start_index..end_index] }),
        },
    };
}

extern fn tree_sitter_bash() callconv(.c) *ts.Language;

test "textDocument/hover" {
    // const allocator = std.testing.allocator;

    const text =
        \\ #!/bin/bash
        \\ set -e
        \\
        \\ echo "echo echo"
        \\ 
        \\ function _get_git_branch() {
        \\   output="$(git branch --show-current 2>/dev/null)"
        \\   if [ $? -eq 0 ]; then
        \\       echo '   '"$output"
        \\   fi
        \\    unset output
        \\ }
        \\
        \\ function _bash_prompt() {
        \\  PS1='\[\033[01;36m\]\W\[\033[01;31m\]$(_get_git_branch)\n\[\033[01;32m\]> \[\033[00m\]'
        \\ }
    ;

    const lang = tree_sitter_bash();
    defer lang.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();

    try parser.setLanguage(lang);

    const tree = parser.parseString(text, null) orelse return;
    defer tree.destroy();

    const root_node = tree.rootNode();

    var point = ts.Point{ .row = 5, .column = 12 };
    var node = root_node.descendantForPointRange(point, point);
    try std.testing.expect(node != null);
    var node_text = text[node.?.startByte()..node.?.endByte()];
    try std.testing.expectEqualStrings(node_text, "_get_git_branch");

    point = ts.Point{ .row = 10, .column = 5 };
    node = root_node.descendantForPointRange(point, point);
    try std.testing.expect(node != null);
    node_text = text[node.?.startByte()..node.?.endByte()];
    try std.testing.expectEqualStrings(text[node.?.startByte()..node.?.endByte()], "unset");

    point = ts.Point{ .row = 8, .column = 8 };
    node = root_node.descendantForPointRange(point, point);
    try std.testing.expect(node != null);
    node_text = text[node.?.startByte()..node.?.endByte()];
    try std.testing.expectEqualStrings(text[node.?.startByte()..node.?.endByte()], "echo");

    point = ts.Point{ .row = 14, .column = 3 };
    node = root_node.descendantForPointRange(point, point);
    try std.testing.expect(node != null);
    node_text = text[node.?.startByte()..node.?.endByte()];
    try std.testing.expectEqualStrings(text[node.?.startByte()..node.?.endByte()], "PS1");
}
