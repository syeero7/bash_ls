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

pub fn sendErrorResponse(writer: *Io.Writer, arena: Allocator, err: types.ResponseError) !void {
    try writeResponse(writer, arena, err, .{});
}

pub fn sendResultResponse(
    writer: *Io.Writer,
    arena: Allocator,
    comptime T: type,
    result: types.ResponseResult(T),
    options: json.Stringify.Options,
) !void {
    try writeResponse(writer, arena, result, options);
}

pub fn writeResponse(
    writer: *Io.Writer,
    arena: Allocator,
    data: anytype,
    options: json.Stringify.Options,
) !void {
    const msg = try encodeJsonRpc(arena, data, options);
    try writer.writeAll(msg);
    try writer.flush();
}

const field_separator = "\r\n\r\n";
const header_field_name = "Content-Length: ";

pub fn encodeJsonRpc(arena: Allocator, json_struct: anytype, options: json.Stringify.Options) ![]u8 {
    const content = try json.Stringify.valueAlloc(arena, json_struct, options);
    std.log.debug("json string: {s}", .{content});
    const fmt = header_field_name ++ "{d}" ++ field_separator ++ "{s}";
    return std.fmt.allocPrint(arena, fmt, .{ content.len, content });
}

fn decodeJsonRpc(comptime T: type, reader: *std.Io.Reader, arena: Allocator) !json.Parsed(T) {
    const content = try getJsonContent(reader, arena);
    return try json.parseFromSlice(T, arena, content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

fn getJsonContent(reader: *std.Io.Reader, arena: Allocator) ![]u8 {
    const line = try reader.takeDelimiterInclusive('\n');
    if (!std.mem.endsWith(u8, line, field_separator[0..2])) return error.SeparatorNotFound;
    const separator_rest = try reader.takeArray(2);
    if (!std.mem.eql(u8, separator_rest, field_separator[2..])) return error.SeparatorNotFound;

    if (std.mem.cut(u8, line[0..(line.len - 2)], header_field_name)) |parts| {
        const content_length = try std.fmt.parseInt(usize, parts.@"1", 10);
        const content = try reader.readAlloc(arena, content_length);
        std.log.debug("content: {s}", .{content});
        return content;
    }

    return error.ContentLengthNotFound;
}

test "encode json-rpc" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const msg = struct { @"test": bool = true }{};
    const result = try encodeJsonRpc(allocator, msg, .{});

    try testing.expectEqualStrings(result, header_field_name ++ "13" ++ field_separator ++ "{\"test\":true}");
}

test "decode json-rpc" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var test_reader = std.Io.Reader.fixed(header_field_name ++ "13" ++ field_separator ++ "{\"test\":true}");
    const test_struct = struct { @"test": bool = true };
    const result = try decodeJsonRpc(test_struct, &test_reader, allocator);
    defer result.deinit();

    try testing.expectEqual(result.value.@"test", true);
}
