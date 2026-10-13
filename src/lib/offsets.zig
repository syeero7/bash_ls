const std = @import("std");
const types = @import("../lsp/types.zig");
const testing = std.testing;

const Position = types.Position;
const Encoding = types.PositionEncodingKind;

pub fn positionToIndex(text: []const u8, position: Position, encoding: Encoding) usize {
    _ = encoding;
    var line_number: u32 = 0;
    var line_start_index: usize = 0;
    for (text, 0..) |char, i| {
        if (line_number == position.line) break;
        if (char == '\n') {
            line_number += 1;
            line_start_index = i + 1;
        }
    } else return text.len;

    const line: []const u8 = std.mem.sliceTo(text[line_start_index..], '\n');
    return line_start_index + @min(line.len, position.character);
}

pub fn getRelativeEndPosition(start: Position, end: Position) Position {
    return .{
        .line = end.line - start.line,
        .character = if (start.line == end.line) end.character - start.character else end.character,
    };
}

test "position to index" {
    const text = "# petals fall\nwithout a trace.\n the game is \nfixed!\n";
    var position: Position = .{ .line = 1, .character = 5 };
    var index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == 'u');

    position = .{ .line = 3, .character = 2 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == 'x');

    position = .{ .line = 0, .character = 0 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == '#');

    position = .{ .line = 3, .character = 99 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == '\n');

    position = .{ .line = 99, .character = 99 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(index == text.len);
}

test "calculate offsets" {
    const text = "by the phantasmoon\n I'll vanquish you!\n you've stepped out of\n line\n";
    const selected_text = "I'll vanquish you!\n you've stepped out of\n line";
    const start_position: Position = .{ .line = 1, .character = 1 };
    const end_position: Position = .{ .line = 3, .character = 5 };

    const start_index = positionToIndex(text, start_position, .@"utf-8");
    const relative_end = getRelativeEndPosition(start_position, end_position);
    const end_index = positionToIndex(text[start_index..], relative_end, .@"utf-8");

    try testing.expectEqualStrings(selected_text, text[start_index..(start_index + end_index)]);
    try testing.expect(selected_text.len == (start_index + end_index) - start_index);
}
