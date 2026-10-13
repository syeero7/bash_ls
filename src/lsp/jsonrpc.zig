const std = @import("std");
const types = @import("types.zig");

const json = std.json;
const testing = std.testing;

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn parseMessage(reader: *Io.Reader, allocator: Allocator) !json.Parsed(types.Message) {
    return decodeJsonRpc(types.Message, reader, allocator);
}

pub fn parseParams(allocator: Allocator, comptime T: type, value: json.Value) !json.Parsed(T) {
    return try json.parseFromValue(T, allocator, value, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

pub fn sendErrorResponse(writer: *Io.Writer, allocator: Allocator, err: types.ResponseError) !void {
    const msg = try encodeJsonRpc(allocator, err);
    defer allocator.free(msg);
    try writer.writeAll(msg);
    try writer.flush();
}

pub fn sendResultResponse(
    writer: *Io.Writer,
    allocator: Allocator,
    comptime T: type,
    result: types.ResponseResult(T),
) !void {
    const msg = try encodeJsonRpc(allocator, result);
    defer allocator.free(msg);
    try writer.writeAll(msg);
    try writer.flush();
}

pub fn sendNotification(writer: *Io.Writer, allocator: Allocator, notification: types.Notification) !void {
    const msg = try encodeJsonRpc(allocator, notification);
    defer allocator.free(msg);
    try writer.writeAll(msg);
    try writer.flush();
}

pub fn sendParseErrorResponse(writer: *Io.Writer, allocator: Allocator, id: ?types.ID) !void {
    try sendErrorResponse(writer, allocator, .{
        .id = id,
        .@"error" = .{
            .code = .parse_error,
            .message = "failed to parse the message",
        },
    });
}

const field_separator = "\r\n\r\n";
const header_field_name = "Content-Length: ";

pub fn encodeJsonRpc(allocator: Allocator, json_struct: anytype) ![]u8 {
    const content = try json.Stringify.valueAlloc(allocator, json_struct, .{});
    std.log.debug("json string: {s}", .{content});
    defer allocator.free(content);
    const fmt = header_field_name ++ "{d}" ++ field_separator ++ "{s}";
    return std.fmt.allocPrint(allocator, fmt, .{ content.len, content });
}

fn decodeJsonRpc(comptime T: type, reader: *std.Io.Reader, allocator: Allocator) !json.Parsed(T) {
    const content = try getJsonContent(reader, allocator);
    defer allocator.free(content);
    return try json.parseFromSlice(T, allocator, content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

fn getJsonContent(reader: *std.Io.Reader, allocator: Allocator) ![]u8 {
    const line = try reader.takeDelimiterInclusive('\n');
    if (!std.mem.endsWith(u8, line, field_separator[0..2])) return error.SeparatorNotFound;
    const separator_rest = try reader.takeArray(2);
    if (!std.mem.eql(u8, separator_rest, field_separator[2..])) return error.SeparatorNotFound;

    if (std.mem.cut(u8, line[0..(line.len - 2)], header_field_name)) |parts| {
        const content_length = try std.fmt.parseInt(usize, parts.@"1", 10);
        const content = try reader.readAlloc(allocator, content_length);
        std.log.debug("content: {s}", .{content});
        return content;
    }

    return error.ContentLengthNotFound;
}

test "encode json-rpc" {
    const allocator = testing.allocator;
    const msg = struct { @"test": bool = true }{};
    const result = try encodeJsonRpc(allocator, msg);
    defer allocator.free(result);

    try testing.expectEqualStrings(result, header_field_name ++ "13" ++ field_separator ++ "{\"test\":true}");
}

test "decode json-rpc" {
    const allocator = testing.allocator;
    var test_reader = std.Io.Reader.fixed(header_field_name ++ "13" ++ field_separator ++ "{\"test\":true}");
    const test_struct = struct { @"test": bool = true };
    const result = try decodeJsonRpc(test_struct, &test_reader, allocator);
    defer result.deinit();

    try testing.expectEqual(result.value.@"test", true);
}
