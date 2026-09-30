const std = @import("std");
const protocol = @import("protocol.zig");

const Allocator = std.mem.Allocator;
const Map = std.StringHashMap([]u8);

pub const DocumentSync = struct {
    documents: Map = undefined,
    encoding: protocol.PositionEncodingKind = .@"utf-16",

    pub fn init(allocator: Allocator) @This() {
        return .{ .documents = .init(allocator) };
    }

    pub fn setPositionEncoding(self: *@This(), encoding: protocol.PositionEncodingKind) void {
        self.encoding = encoding;
    }

    pub fn deinit(self: *@This()) void {
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

    // pub fn didChange(self: *@This(), allocator: Allocator, params: protocol.DidChangeTextDocumentParams) !void {}
    //
    // pub fn didClose(self: *@This(), allocator: Allocator, params: protocol.DidCloseTextDocumentParams) !void {}
};
