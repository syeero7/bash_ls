const std = @import("std");
const json = std.json;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Integer = i32;
const UInteger = u32;
const Decimal = f32;
const String = []const u8;
const LSPAny = json.Value;
const LSPObject = std.StringHashMap(LSPAny);
const LSPArray = []LSPAny;

pub const ID = union(enum) {
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

pub const Message = struct {
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

pub const ResponseError = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?ID = null,
    @"error": struct {
        code: ErrorCode,
        message: String = undefined,
        data: ?LSPAny = null,
    },
};

pub fn ResponseResult(comptime T: type) type {
    return struct {
        jsonrpc: []const u8 = "2.0",
        id: ?ID = null,
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
    hoverProvider: ?bool = null, // HoverOptions;
    definitionProvider: ?bool = null, //DefinitionOptions;
    referencesProvider: ?bool = null, // ReferenceOptions;
    completionProvider: ?CompletionOptions = null,

    // signatureHelpProvider?: SignatureHelpOptions;
    // declarationProvider?: boolean | DeclarationOptions
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

pub const HoverParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
    // workDoneToken: ?ProgressToken,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

pub const MarkupContent = struct {
    kind: MarkupKind,
    value: String,
};

pub const DefinitionPrams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
    // partialResultToken: ?ProgressToken;
    // workDoneToken: ?ProgressToken,
};

pub const DefinitionResult = Location;

pub const Location = struct {
    uri: String,
    range: Range,
};

pub const ReferenceParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
    context: ReferenceContext,
    // partialResultToken: ?ProgressToken;
    // workDoneToken: ?ProgressToken,

};

const ReferenceContext = struct { includeDeclaration: bool };

pub const ReferenceResult = []Location;

pub const CompletionOptions = struct {
    triggerCharacters: ?[]const String = null,
    // allCommitCharacters?: string[];
    resolveProvider: ?bool,
    // completionItem?: ServerCompletionItemOptions;
};

pub const CompletionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
    context: ?CompletionContext = null,
    // partialResultToken: ?ProgressToken;
    // workDoneToken: ?ProgressToken,
};

pub const CompletionResult = []CompletionItem;

pub const CompletionItem = struct {
    label: String,
    kind: ?CompletionItemKind = null,
    detail: ?String = null,
    documentation: ?MarkupContent = null, //?String
    // sortText: ?String = null,
    // filterText: ?String = null,
    // labelDetails: ?CompletionItemLabelDetails = null ,
    // tags?: CompletionItemTag[];
    // preselect:? bool,
    // insertText: ?String = null,
    // insertTextFormat: ?InsertTextFormat ,
    // insertTextMode: ?InsertTextMode,
    // textEdit?: TextEdit | InsertReplaceEdit;
    // textEditText?: string;
    // additionalTextEdits?: TextEdit[];
    // commitCharacters:? String[],
    // command?: Command;
    // data?: LSPAny;
};

const CompletionContext = struct {
    triggerKind: CompletionTriggerKind,
    triggerCharacter: ?String = null,
};

pub const CompletionTriggerKind = enum(u8) {
    invoked = 1,
    triggerCharacter = 2,
    triggerForIncompleteCompletions = 3,

    pub fn jsonStringify(self: @This(), stream: anytype) !void {
        try stream.write(@intFromEnum(self));
    }
};

pub const CompletionItemKind = enum(u8) {
    text = 1,
    function = 3,
    variable = 6,
    unit = 11,
    value = 12,
    keyword = 14,
    snippet = 15,
    color = 16,
    file = 17,
    folder = 19,

    pub fn jsonStringify(self: @This(), stream: anytype) !void {
        try stream.write(@intFromEnum(self));
    }
};
