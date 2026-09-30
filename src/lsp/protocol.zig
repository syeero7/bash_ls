const std = @import("std");
const json = std.json;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Integer = i32;
pub const UInteger = u32;
pub const Decimal = f32;
pub const String = []const u8;
pub const LSPAny = json.Value;
pub const LSPObject = std.StringHashMap(LSPAny);
pub const LSPArray = []LSPAny;

const ID = union(enum) {
    integer: i64,
    string: String,

    pub fn jsonParse(allocator: Allocator, source: anytype, options: json.ParseOptions) !@This() {
        return switch (try json.innerParse(json.Value, allocator, source, options)) {
            .integer => |integer| .{ .integer = integer },
            .string => |string| .{ .string = string },
            else => error.UnexpectedToken,
        };
    }

    pub fn jsonStringify(self: @This(), stream: anytype) !void {
        switch (self) {
            inline else => |value| try stream.write(value),
        }
    }
};

const Message = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?ID = null,
    method: String = undefined,
    params: ?LSPAny = null,
};

const Request = struct {
    jsonrpc: []const u8 = "2.0",
    id: ID = undefined,
    method: String = undefined,
    params: ?LSPAny = null,
};

const ErrorCode = enum(Integer) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,
    server_not_initialized = -32002,
    unknown_error_code = -32001,
    request_failed = -32803,
    server_cancelled = -32802,
    content_modified = -32801,
    request_cancelled = -32800,

    /// server can't handle the protocol version provided by the client
    initialize_error = 1,

    pub fn jsonStringify(self: @This(), stream: anytype) !void {
        try stream.write(@intFromEnum(self));
    }
};

const ResponseError = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?ID = null,
    @"error": struct {
        code: ErrorCode,
        message: String = undefined,
        data: ?LSPAny = null,
    },
};

fn ResponseResult(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: ID = undefined,
        result: ?T = null,
    };
}

const Notification = struct {
    jsonrpc: []const u8 = "2.0",
    method: String = undefined,
    params: ?LSPAny = null,
};

pub const InitializeParams = struct {
    processId: ?Integer = null,
    clientInfo: ?ClientInfo = null,
    rootPath: ?String = null,
    rootUri: ?String = null,
    initializeOptions: ?InitializationOptions = null,
    capabilities: ClientCapabilities = undefined,

    // trace: ?TraceValue = null,
    // workspaceFolders: ?[]WorkspaceFolder = null,
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ?ServerInfo = null,
};

pub const ServerClientInfo = struct {
    name: String = undefined,
    version: ?String = null,
};

pub const ClientInfo = ServerClientInfo;

pub const ServerInfo = ServerClientInfo;

pub const ClientCapabilities = struct {
    textDocument: ?TextDocumentClientCapabilities = null,
    general: ?GeneralClientCapabilities = null,

    // workspace: ?WorkspaceClientCapabilities = null,
    // window: ?WindowClientCapabilities = null,

    pub fn supportUtf8Encoding(self: @This()) bool {
        if (self.general) |general| {
            if (general.positionEncodings) |encodings| {
                for (encodings) |value| {
                    if (value == .@"utf-8") return true;
                }
            }
        }

        return false;
    }
};

// NOTE: for lsp config i guess
pub const InitializationOptions = LSPAny;

pub const TextDocumentClientCapabilities = struct {
    hover: ?HoverClientCapabilities = null,
    // synchronization: ?TextDocumentSyncClientCapabilities = null,
    // completion: ?CompletionClientCapabilities = null,
    // diagnostic: ?DiagnosticClientCapabilities = null,
    // definition: ?DefinitionClientCapabilities = null,
    // references: ?ReferenceClientCapabilities = null,
    // codeAction: ?CodeActionClientCapabilities = null,
    // rename: ?RenameClientCapabilities = null,
    // foldingRange: ?FoldingRangeClientCapabilities = null,

    // signatureHelp: ?SignatureHelpClientCapabilities = null,
    // declaration: ?DeclarationClientCapabilities = null,
    // typeDefinition: ?TypeDefinitionClientCapabilities = null,
    // implementation: ?ImplementationClientCapabilities = null,
    // documentHighlight: ?DocumentHighlightClientCapabilities = null,
    // documentSymbol: ?DocumentSymbolClientCapabilities = null,
    // codeLens: ?CodeLensClientCapabilities = null,
    // documentLink: ?DocumentLinkClientCapabilities = null,
    // colorProvider: ?DocumentColorClientCapabilities = null,
    // formatting: ?DocumentFormattingClientCapabilities = null,
    // rangeFormatting: ?DocumentRangeFormattingClientCapabilities = null,
    // onTypeFormatting: ?DocumentOnTypeFormattingClientCapabilities = null,
    // publishDiagnostics: ?PublishDiagnosticsClientCapabilities = null,
    // selectionRange: ?SelectionRangeClientCapabilities = null,
    // linkedEditingRange: ?LinkedEditingRangeClientCapabilities = null,
    // semanticTokens: ?SemanticTokensClientCapabilities = null,
    // moniker: ?MonikerClientCapabilities = null,
    // typeHierarchy: ?TypeHierarchyClientCapabilities = null,
    // inlineValue: ?InlineValueClientCapabilities = null,
    // inlayHint: ?InlayHintClientCapabilities = null,
    // inlineCompletion: ?InlineCompletionClientCapabilities = null,
};

pub const HoverClientCapabilities = struct {
    dynamicRegistration: ?bool = null,
    contentFormat: ?[]MarkupKind = null,
};

pub const MarkupKind = enum { plaintext, markdown };

pub const WorkspaceClientCapabilities = struct {
    // applyEdit: ?bool = null,
    // workspaceEdit: ?WorkspaceEditClientCapabilities = null,
    // didChangeWatchedFiles: ?DidChangeWatchedFilesClientCapabilities = null,
    // symbol: ?WorkspaceSymbolClientCapabilities = null,
    // executeCommand: ?ExecuteCommandClientCapabilities = null,
    // semanticTokens: ?SemanticTokensWorkspaceClientCapabilities = null,
    // codeLens: ?CodeLensWorkspaceClientCapabilities = null,
    // fileOperations: ?FileOperationClientCapabilities = null,
    // inlineValue: ?InlineValueWorkspaceClientCapabilities = null,
    // inlayHint: ?InlayHintWorkspaceClientCapabilities = null,
    // diagnostics: ?DiagnosticWorkspaceClientCapabilities = null,
    // foldingRange: ?FoldingRangeWorkspaceClientCapabilities = null,
    // textDocumentContent: ?TextDocumentContentClientCapabilities = null,
};

pub const FileOperationClientCapabilities = struct {
    // dynamicRegistration: ?bool = null,
    // didCreate: ?bool = null,
    // willCreate: ?bool = null,
    // didRename: ?bool = null,
    // willRename: ?bool = null,
    // didDelete: ?bool = null,
    // willDelete: ?bool = null,
};

pub const WindowClientCapabilities = struct {
    // workDoneProgress: ?bool = null,
    // showMessage: ?ShowMessageRequestClientCapabilities = null,
    // showDocument: ?ShowDocumentClientCapabilities = null,
};

pub const GeneralClientCapabilities = struct {
    // staleRequestSupport: ?StaleRequestSupportOptions = null,
    // regularExpressions: ?RegularExpressionsClientCapabilities = null,
    // markdown: ?MarkdownClientCapabilities = null,
    positionEncodings: ?[]PositionEncodingKind = null,
};

pub const PositionEncodingKind = enum {
    @"utf-8",
    @"utf-16",
    @"utf-32",
};

pub const StaleRequestSupportOptions = struct {
    cancel: bool,
    retryOnContentModified: []String,
};

pub const ServerCapabilities = struct {
    positionEncoding: ?PositionEncodingKind = null,
    textDocumentSync: ?TextDocumentSyncOptions = null,

    // completionProvider?: CompletionOptions;
    hoverProvider: ?bool = null, // HoverOptions;
    // signatureHelpProvider?: SignatureHelpOptions;
    // declarationProvider?: boolean | DeclarationOptions
    // definitionProvider?: boolean | DefinitionOptions;
    // typeDefinitionProvider?: boolean | TypeDefinitionOptions
    //  TypeDefinitionRegistrationOptions;
    // implementationProvider?: boolean | ImplementationOptions
    //  ImplementationRegistrationOptions;
    // referencesProvider?: boolean | ReferenceOptions;
    // documentHighlightProvider?: boolean | DocumentHighlightOptions;
    // documentSymbolProvider?: boolean | DocumentSymbolOptions;
    // codeActionProvider?: boolean | CodeActionOptions;
    // codeLensProvider?: CodeLensOptions;
    // documentLinkProvider?: DocumentLinkOptions;
    // colorProvider?: boolean | DocumentColorOptions
    //  DocumentColorRegistrationOptions;
    // renameProvider?: boolean | RenameOptions;
    // foldingRangeProvider?: boolean | FoldingRangeOptions
    //  FoldingRangeRegistrationOptions;
    // executeCommandProvider?: ExecuteCommandOptions;
    // selectionRangeProvider?: boolean | SelectionRangeOptions
    //  SelectionRangeRegistrationOptions;
    // linkedEditingRangeProvider?: boolean | LinkedEditingRangeOptions
    //  LinkedEditingRangeRegistrationOptions;
    //
    // semanticTokensProvider?: SemanticTokensOptions
    //  SemanticTokensRegistrationOptions;
    // monikerProvider?: boolean | MonikerOptions | MonikerRegistrationOptions;
    // typeHierarchyProvider?: boolean | TypeHierarchyOptions
    //  TypeHierarchyRegistrationOptions;
    // inlineValueProvider?: boolean | InlineValueOptions
    //  InlineValueRegistrationOptions;
    //
    // inlayHintProvider?: boolean | InlayHintOptions
    //  InlayHintRegistrationOptions;
    //
    // diagnosticProvider?: DiagnosticOptions | DiagnosticRegistrationOptions;
    // workspaceSymbolProvider?: boolean | WorkspaceSymbolOptions;
    // inlineCompletionProvider?: boolean | InlineCompletionOptions;
    // workspace?: WorkspaceOptions;
};

pub const WorkspaceOptions = struct {
    // workspaceFolders?: WorkspaceFoldersServerCapabilities;
    // fileOperations?: FileOperationOptions;
    // textDocumentContent?: TextDocumentContentOptions
    //  TextDocumentContentRegistrationOptions;
};

pub const FileOperationOptions = struct {
    // didCreate?: FileOperationRegistrationOptions;
    // willCreate?: FileOperationRegistrationOptions;
    // didRename?: FileOperationRegistrationOptions;
    // willRename?: FileOperationRegistrationOptions;
    // didDelete?: FileOperationRegistrationOptions;
    // willDelete?: FileOperationRegistrationOptions;
};

pub const TextDocumentSyncOptions = struct {
    openClose: ?bool,
    change: ?TextDocumentSyncKind,
};

pub const TextDocumentSyncKind = enum(u8) {
    none = 0,
    full = 1,
    incremental = 2,

    pub fn jsonStringify(self: @This(), stream: anytype) !void {
        try stream.write(@intFromEnum(self));
    }
};

pub const DidOpenTextDocumentParams = struct {
    textDocument: TextDocumentItem,
};

pub const TextDocumentItem = struct {
    uri: String,
    languageId: String,
    version: Integer,
    text: String,
};

pub const Range = struct {
    start: Position,
    end: Position,
};
pub const Position = struct {
    line: UInteger,
    character: UInteger,
};

pub const DidChangeTextDocumentParams = struct {
    textDocument: VersionedTextDocumentIdentifier,
    contentChanges: []TextDocumentContentChangeEvent,
};

pub const VersionedTextDocumentIdentifier = struct {
    uri: String,
    version: Integer,
};

pub const TextDocumentContentChangeEvent = struct {
    /// range is null if client sent the whole document
    range: ?Range = null,
    text: String,
};

pub const DidCloseTextDocumentParams = struct {
    textDocument: TextDocumentIdentifier,
};

pub const TextDocumentIdentifier = struct {
    uri: String,
};

pub fn parseMessage(reader: *Io.Reader, allocator: Allocator) !json.Parsed(Message) {
    return decodeJsonRpc(Message, reader, allocator);
}

pub fn parseParams(allocator: Allocator, comptime T: type, value: json.Value) !json.Parsed(T) {
    return try json.parseFromValue(T, allocator, value, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

pub fn sendErrorResponse(writer: *Io.Writer, allocator: Allocator, err: ResponseError) !void {
    const msg = try encodeJsonRpc(allocator, err);
    defer allocator.free(msg);
    try writer.writeAll(msg);
    try writer.flush();
}

pub fn sendResultResponse(
    writer: *Io.Writer,
    allocator: Allocator,
    comptime T: type,
    result: ResponseResult(T),
) !void {
    const msg = try encodeJsonRpc(allocator, result);
    defer allocator.free(msg);
    try writer.writeAll(msg);
    try writer.flush();
}

pub fn sendNotification(writer: *Io.Writer, allocator: Allocator, notification: Notification) !void {
    const msg = try encodeJsonRpc(allocator, notification);
    defer allocator.free(msg);
    try writer.writeAll(msg);
    try writer.flush();
}

pub fn sendParseErrorResponse(writer: *Io.Writer, allocator: Allocator, id: ?ID) !void {
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

fn encodeJsonRpc(allocator: Allocator, json_struct: anytype) ![]u8 {
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
