const std = @import("std");
const json = std.json;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const field_separator = [_]u8{ '\r', '\n', '\r', '\n' };
const header_field_name = "Content-Length: ";

const Message = struct {
    jsonrpc: []const u8 = "2.0",
    id: u64 = undefined,
    method: []const u8 = undefined,
    // params :
};

pub fn encode(allocator: Allocator, json_struct: anytype) ![]u8 {
    const content = try json.Stringify.valueAlloc(allocator, json_struct, .{});
    defer allocator.free(content);
    const fmt = header_field_name ++ "{d}" ++ field_separator ++ "{s}";
    return std.fmt.allocPrint(allocator, fmt, .{ content.len, content });
}

pub fn decode(comptime T: type, reader: *std.Io.Reader, allocator: Allocator) !json.Parsed(T) {
    const content = try getContent(reader, allocator);
    defer allocator.free(content);
    return try json.parseFromSlice(T, allocator, content, .{ .ignore_unknown_fields = true });
}

pub fn getContent(reader: *std.Io.Reader, allocator: Allocator) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    defer alloc_writer.deinit();

    _ = try reader.streamDelimiter(&alloc_writer.writer, '\n');
    const line = alloc_writer.written();
    if (!std.mem.endsWith(u8, line, "\r")) return error.SeparatorNotFound;
    const separator_rest = try reader.takeArray(3);
    if (!std.mem.eql(u8, separator_rest, "\n\r\n")) return error.SeparatorNotFound;

    if (std.mem.cut(u8, line[0..(line.len - 1)], header_field_name)) |parts| {
        const content_length = try std.fmt.parseInt(usize, parts.@"1", 10);
        return try reader.readAlloc(allocator, content_length);
    }

    return error.ContentLengthNotFound;
}

test "encode json" {
    const allocator = testing.allocator;
    const msg = struct { @"test": bool = true }{};
    const result = try encode(allocator, msg);
    defer allocator.free(result);

    try testing.expectEqualStrings(result, header_field_name ++ "13" ++ field_separator ++ "{\"test\":true}");
}

test "decode json" {
    const allocator = testing.allocator;
    var test_reader = std.Io.Reader.fixed(header_field_name ++ "13" ++ field_separator ++ "{\"test\":true}");
    const test_struct = struct { @"test": bool = true };
    const result = try decode(test_struct, &test_reader, allocator);
    defer result.deinit();

    try testing.expectEqual(result.value.@"test", true);
}
