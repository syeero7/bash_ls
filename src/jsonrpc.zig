const std = @import("std");
const json = std.json;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Integer = i32;

pub const UInteger = u32;

pub const Decimal = f32;

pub const String = []const u8;

pub const LSPObject = std.StringHashMap(LSPAny);

pub const LSPArray = std.ArrayList(LSPAny);

pub const LSPAny = union(enum) {
    lsp_array: LSPArray,
    lsp_object: LSPObject,
    string: String,
    initeger: Integer,
    uninteger: UInteger,
    decimal: Decimal,
    boolean: bool,
    null: null,
};

pub const RequestMessage = struct {
    jsonrpc: []const u8 = "2.0",
    id: Integer = undefined,
    method: String = undefined,
    params: type = null,
};

pub const ResponseMessage = struct {
    jsonrpc: []const u8 = "2.0",
    id: Integer = undefined,
    result: LSPAny = null,
    @"error": ResponseError = null,
};

pub const Error = error{
    ParseError,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
    ServerNotInitialized,
    UnknownErrorCode,
    RequestFailed,
    ServerCancelled,
    ContentModified,
    RequestCancelled,
};

pub const ResponseError = struct {
    code: Integer = undefined,
    message: String = undefined,
    data: LSPAny = null,

    pub fn init(err: Error, msg: String, data: ?LSPAny) ResponseError {
        return .{
            .message = msg,
            .data = data,
            .code = switch (err) {
                .ParseError => Integer(-32700),
                .InvalidRequest => Integer(-32600),
                .MethodNotFound => Integer(-32601),
                .InvalidParams => Integer(-32602),
                .InternalError => Integer(-32603),
                .ServerNotInitialized => Integer(-32002),
                .UnknownErrorCode => Integer(-32001),
                .RequestFailed => Integer(-32803),
                .ServerCancelled => Integer(-32802),
                .ContentModified => Integer(-32801),
                .RequestCancelled => Integer(-32800),
            },
        };
    }
};

pub const NotificationMessage = struct {
    jsonrpc: []const u8 = "2.0",
    method: String = undefined,
    params: type = null,
};

const field_separator = [_]u8{ '\r', '\n', '\r', '\n' };
const header_field_name = "Content-Length: ";

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
