const std = @import("std");
const ts = @import("tree_sitter");
const types = @import("lsp/types.zig");

const Allocator = std.mem.Allocator;

const Position = types.Position;
const Encoding = types.PositionEncodingKind;

const Handler = @This();

const State = enum {
    not_initialized,
    initialized,
    shutdown,
};

documents: std.StringHashMap([]u8) = undefined,
encoding: Encoding = .@"utf-16",
server_state: State = .not_initialized,
lang: *ts.Language,
parser: *ts.Parser,

pub fn initialize(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    params: types.InitializeParams,
) !types.InitializeResult {
    if (params.capabilities.supportUtf8Encoding()) self.encoding = .@"utf-8";

    // FIXME: support utf-16 position encoding
    std.debug.assert(self.encoding == .@"utf-8");

    return .{
        .capabilities = .{
            .positionEncoding = self.encoding,
            .textDocumentSync = .{
                .openClose = true,
                .change = .incremental,
            },
            .hoverProvider = true,
            .definitionProvider = true,
            .referencesProvider = true,
        },
        .serverInfo = .{
            .name = "bash_ls",
            .version = "v0.0.1",
        },
    };
}

pub fn initialized(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    _: void,
) void {
    self.server_state = .initialized;
}

pub fn shutdown(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    _: void,
) ?void {
    self.server_state = .shutdown;
    return null;
}

pub fn exit(
    self: *@This(),
    _: Allocator,
    _: Allocator,
    _: void,
) !void {
    if (self.server_state == .shutdown) return error.ExitServer;
    return error.ExitWithoutShutdown;
}

pub fn @"textDocument/hover"(
    self: *@This(),
    gpa: Allocator,
    arena: Allocator,
    params: types.HoverParams,
) !types.Hover {
    _ = self;
    _ = gpa;

    // TODO:
    return .{ .contents = .{
        .kind = .plaintext,
        .value = try std.fmt.allocPrint(arena, "[some thing] {s}\n other thing {s}", .{
            "stuff",
            params.textDocument.uri,
        }),
    } };
}

pub fn init(gpa: Allocator, language: *ts.Language, parser: *ts.Parser) @This() {
    return .{ .documents = .init(gpa), .lang = language, .parser = parser };
}

pub fn deinit(self: *@This(), gpa: Allocator) void {
    var doc_iterator = self.documents.iterator();
    while (doc_iterator.next()) |entry| {
        gpa.free(entry.key_ptr.*);
        gpa.free(entry.value_ptr.*);
    }

    self.documents.deinit();
    self.* = undefined;
}
