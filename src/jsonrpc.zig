const std = @import("std");
const json = std.json;
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Integer = i32;

pub const UInteger = u32;

pub const Decimal = f32;

pub const String = []const u8;

pub const LSPAny = json.Value;

pub const LSPObject = std.StringHashMap(LSPAny);

pub const LSPArray = []LSPAny;

pub fn Request(T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: Integer = undefined,
        method: String = undefined,
        params: ?T = null,
    };
}

const ResponseKind = enum { err, result };

pub fn Response(T: type, _: ResponseKind) type {
    if (@hasField(T, "code")) {
        return struct {
            jsonrpc: []const u8 = "2.0",
            id: ?Integer = null,
            @"error": T = undefined,
        };
    }

    return struct {
        jsonrpc: []const u8 = "2.0",
        id: Integer = undefined,
        result: T = undefined,
    };
}

pub const ErrorCode = enum(Integer) {
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

    initialize_error = 1,
};

pub fn ResponseError(err_code: ErrorCode, T: anytype) type {
    return struct {
        code: Integer = @intFromEnum(err_code),
        message: String = undefined,
        data: T,
    };
}

pub fn Notification(T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        method: String = undefined,
        params: ?T = null,
    };
}

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

pub const InitializeResultResponse = Response(InitializeResult, .result);

pub const InitializeErrorData = struct { retry: bool = false };

pub const InitializeError = ResponseError(.initialize_error, InitializeErrorData);

pub const InitializeErrorResponse = Response(InitializeError, .err);

pub const ServerNotInitialized = ResponseError(.server_not_initialized, InitializeErrorData);

pub const NotInitializedResponse = Response(ServerNotInitialized, .err);

pub const ServerClientInfo = struct {
    name: String = undefined,
    version: ?String = null,
};

pub const ClientInfo = ServerClientInfo;

pub const ServerInfo = ServerClientInfo;

pub const ClientCapabilities = struct {
    textDocument: ?TextDocumentClientCapabilities = null,

    // workspace: ?WorkspaceClientCapabilities = null,
    // window: ?WindowClientCapabilities = null,
    // general: ?GeneralClientCapabilities = null,
};

// NOTE: for lsp config i guess
pub const InitializationOptions = LSPAny;

pub const InitializeRequest = Request(InitializeParams);

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
    // positionEncodings: ?[]PositionEncodingKind = null,
};

pub const StaleRequestSupportOptions = struct {
    cancel: bool,
    retryOnContentModified: []String,
};

pub const ServerCapabilities = struct {
    // positionEncoding: ?PositionEncodingKind = null,
    // textDocumentSync?: TextDocumentSyncOptions | TextDocumentSyncKind;
    // completionProvider?: CompletionOptions;
    hoverProvider: ?bool, // HoverOptions;
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

pub const InitializedParams = struct {};

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
    return try json.parseFromSlice(T, allocator, content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
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
        const content = try reader.readAlloc(allocator, content_length);
        std.log.debug("re: {s}\n", .{content});
        return content;
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
