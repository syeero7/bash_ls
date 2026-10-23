const std = @import("std");
const types = @import("../lsp/types.zig");

const unicode = std.unicode;
const testing = std.testing;

const Range = types.Range;
const Position = types.Position;
const Encoding = types.PositionEncodingKind;

const Utf8Range = struct {
    start_index: usize,
    length: usize,
};

pub fn getUtf8Range(text: []const u8, range: Range, encoding: Encoding) Utf8Range {
    const start = positionToIndex(text, range.start, encoding);
    const relative_end = getRelativeEndPosition(range.start, range.end);
    const end = positionToIndex(text[start..], relative_end, encoding);
    const length = (start + end) - start;
    return .{ .start_index = start, .length = length };
}

pub fn positionToIndex(text: []const u8, position: Position, encoding: Encoding) usize {
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
    const line_length = getUtf8Index(line, position.character, encoding);
    return line_start_index + line_length;
}

pub fn getRelativeEndPosition(start: Position, end: Position) Position {
    return .{
        .line = end.line - start.line,
        .character = if (start.line == end.line) end.character - start.character else end.character,
    };
}

fn getUtf8Index(text: []const u8, end_index: usize, encoding: Encoding) usize {
    if (end_index == 0 or text.len == 0) return 0;

    switch (encoding) {
        .@"utf-8" => return @min(text.len, end_index),
        .@"utf-16" => {
            var utf16_length: usize = 0;
            var utf8_iterator = unicode.Utf8Iterator{ .bytes = text, .i = 0 };
            while (utf8_iterator.nextCodepoint()) |codepoint| {
                utf16_length += unicode.utf16CodepointSequenceLength(codepoint) catch unreachable;
                if (utf16_length == end_index) break;
            }

            return utf8_iterator.i;
        },
        .@"utf-32" => {
            var codepoint_count: usize = 0;
            var utf8_iterator = unicode.Utf8Iterator{ .bytes = text, .i = 0 };
            while (utf8_iterator.nextCodepoint()) |_| {
                codepoint_count += 1;
                if (codepoint_count == end_index) break;
            }

            return utf8_iterator.i;
        },
    }
}

test "position to index" {
    const text = "#Smile 🙂\nPetals Fall\nWithout ᾼ Trace.\nThé game is BUGGED!\n🧡LESS Watermelon";
    // NOTE: utf8: 🧡 = 4 bytes, ᾼ = 3 bytes, é = 2 bytes

    var position: Position = .{ .line = 1, .character = 5 };
    var index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == 's');

    position = .{ .line = 2, .character = 2 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == 't');

    position = .{ .line = 3, .character = 2 };
    index = positionToIndex(text, position, .@"utf-16");
    try testing.expectEqualStrings("é", text[index .. index + 2]);

    position = .{ .line = 2, .character = 8 };
    index = positionToIndex(text, position, .@"utf-16");
    try testing.expectEqualStrings("ᾼ", text[index .. index + 3]);

    position = .{ .line = 0, .character = 7 };
    index = positionToIndex(text, position, .@"utf-16");
    try testing.expectEqualStrings("🙂", text[index .. index + 4]);

    position = .{ .line = 4, .character = 0 };
    index = positionToIndex(text, position, .@"utf-32");
    try testing.expectEqualStrings("🧡", text[index .. index + 4]);

    position = .{ .line = 3, .character = 99 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(text[index] == '\n');

    position = .{ .line = 99, .character = 99 };
    index = positionToIndex(text, position, .@"utf-8");
    try testing.expect(index == text.len);
}

test "calculate offsets" {
    const text = "The bluetooth\ndevice 🧡 is connécted\nsuccessfully.\nThᾼt unreachable paradise";
    var range: Range = .{
        .start = .{ .line = 1, .character = 0 },
        .end = .{ .line = 3, .character = 18 },
    };

    var utf8_range = getUtf8Range(text, range, .@"utf-8");
    try testing.expectEqualStrings(text[14..72], text[utf8_range.start_index..(utf8_range.start_index + utf8_range.length)]);

    range.end.character = 16;
    utf8_range = getUtf8Range(text, range, .@"utf-16");
    try testing.expectEqualStrings(text[14..72], text[utf8_range.start_index..(utf8_range.start_index + utf8_range.length)]);

    range.end = .{ .line = 1, .character = 21 };
    utf8_range = getUtf8Range(text, range, .@"utf-32");
    try testing.expectEqualStrings(text[14..39], text[utf8_range.start_index..(utf8_range.start_index + utf8_range.length)]);
}
