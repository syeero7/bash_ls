const std = @import("std");
const json = std.json;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const field_separator = [_]u8{ '\r', '\n', '\r', '\n' };

const Message = struct {
    jsonrpc: []const u8 = "2.0",
    id: u64 = undefined,
    method: []const u8 = undefined,
    // params :
};

pub fn encode(allocator: Allocator, json_struct: anytype) ![]u8 {
    const content = try json.Stringify.valueAlloc(allocator, json_struct, .{});
    defer allocator.free(content);
    const fmt = "Content-Length: {d}" ++ field_separator ++ "{s}";
    return std.fmt.allocPrint(allocator, fmt, .{ content.len, content });
}

test "encode json" {
    const allocator = testing.allocator;
    const msg = struct { @"test": bool = true }{};
    const result = try encode(allocator, msg);
    defer allocator.free(result);

    try testing.expectEqualStrings(result, "Content-Length: 13" ++ field_separator ++ "{\"test\":true}");
}
