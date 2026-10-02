const std = @import("std");
const protocol = @import("protocol.zig");

const Allocator = std.mem.Allocator;
const Map = std.StringHashMap([]u8);
const Position = protocol.Position;
const Encoding = protocol.PositionEncodingKind;

pub const TextDocumentSync = struct {
    documents: Map = undefined,
    encoding: Encoding = .@"utf-16",

    pub fn init(allocator: Allocator) @This() {
        return .{ .documents = .init(allocator) };
    }

    pub fn setPositionEncoding(self: *@This(), encoding: Encoding) void {
        self.encoding = encoding;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        var doc_iterator = self.documents.iterator();
        while (doc_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }

        self.documents.deinit();
        self.* = undefined;
    }

    pub fn didOpen(self: *@This(), allocator: Allocator, params: protocol.DidOpenTextDocumentParams) !void {
        const text_document = params.textDocument;
        std.log.debug("file opened. uri {s}", .{text_document.uri});
        const text = try allocator.dupe(u8, text_document.text);
        errdefer allocator.free(text);

        const result = try self.documents.getOrPut(text_document.uri);
        if (result.found_existing) {
            allocator.free(result.value_ptr.*);
            result.value_ptr.* = text;
            return;
        }

        result.key_ptr.* = try allocator.dupe(u8, text_document.uri);
        result.value_ptr.* = text;
    }

    pub fn didChange(self: *@This(), allocator: Allocator, params: protocol.DidChangeTextDocumentParams) !void {
        const current_text = self.documents.getPtr(params.textDocument.uri) orelse return;
        var buffer: std.ArrayList(u8) = .empty;
        errdefer buffer.deinit(allocator);
        try buffer.appendSlice(allocator, current_text.*);

        for (params.contentChanges) |change| {
            if (change.range) |range| {
                const start_index = positionToIndex(buffer.items, range.start, self.encoding);
                const relative_end = getRelativeEndPosition(range.start, range.end);
                const end_index = positionToIndex(buffer.items[start_index..], relative_end, self.encoding);
                const length = (start_index + end_index) - start_index;
                try buffer.replaceRange(allocator, start_index, length, change.text);
                continue;
            }

            // NOTE: if range is null client sent the whole document
            buffer.clearRetainingCapacity();
            try buffer.appendSlice(allocator, change.text);
        }

        const new_text = try buffer.toOwnedSlice(allocator);
        allocator.free(current_text.*);
        current_text.* = new_text;
    }

    // pub fn didClose(self: *@This(), allocator: Allocator, params: protocol.DidCloseTextDocumentParams) !void {}
};

fn positionToIndex(text: []const u8, position: Position, encoding: Encoding) usize {
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

fn getRelativeEndPosition(start: Position, end: Position) Position {
    return .{
        .line = end.line - start.line,
        .character = if (start.line == end.line) end.character - start.character else end.character,
    };
}

test "position to index" {
    const text = "# petals fall\nwithout a trace.\n the game is \nfixed!\n";
    var position: Position = .{ .line = 1, .character = 5 };
    var idx = positionToIndex(text, position, .@"utf-8");
    try std.testing.expect(text[idx] == 'u');

    position = .{ .line = 3, .character = 2 };
    idx = positionToIndex(text, position, .@"utf-8");
    try std.testing.expect(text[idx] == 'x');

    position = .{ .line = 0, .character = 0 };
    idx = positionToIndex(text, position, .@"utf-8");
    try std.testing.expect(text[idx] == '#');

    position = .{ .line = 3, .character = 99 };
    idx = positionToIndex(text, position, .@"utf-8");
    try std.testing.expect(text[idx] == '\n');

    position = .{ .line = 99, .character = 99 };
    idx = positionToIndex(text, position, .@"utf-8");
    try std.testing.expect(idx == text.len);
}

test "calculate offsets" {
    const text = "by the phantasmoon\n I'll vanquish you!\n you've stepped out of\n line\n";
    const selected_text = "I'll vanquish you!\n you've stepped out of\n line";
    const start_position: Position = .{ .line = 1, .character = 1 };
    const end_position: Position = .{ .line = 3, .character = 5 };

    const start_index = positionToIndex(text, start_position, .@"utf-8");
    const relative_end = getRelativeEndPosition(start_position, end_position);
    const end_index = positionToIndex(text[start_index..], relative_end, .@"utf-8");

    try std.testing.expectEqualStrings(selected_text, text[start_index..(start_index + end_index)]);
}
