const std = @import("std");
const ts = @import("tree_sitter");
const server = @import("lsp/server.zig");
const ts_bash = @import("lib/tree_sitter_bash.zig");
const bash_commands = @import("lib/commands.zig");
const Handler = @import("Handler.zig");
const Logger = @import("lib/Logger.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .networking = false,
    .logFn = logFn,
};

var logger = Logger.init();

fn logFn(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime fmt: []const u8,
    args: anytype,
) void {
    logger.log(level, scope, fmt, args);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var commands: ?bash_commands.CommandHelp = null;
    defer logger.deinit(io);

    {
        var arg_iterator = try init.minimal.args.iterateAllocator(init.gpa);
        defer arg_iterator.deinit();

        while (arg_iterator.next()) |arg| {
            if (std.mem.eql(u8, arg, "--log-file")) {
                if (arg_iterator.next()) |log_file_path| {
                    logger.setLogFile(io, log_file_path);
                    continue;
                }
            }

            if (std.mem.eql(u8, arg, "--command-help")) {
                if (arg_iterator.next()) |commands_file_path| {
                    commands = bash_commands.generateCommandHelp(io, init.gpa, commands_file_path) catch null;
                    continue;
                }
            }
        }
    }

    var stdin_buffer: [1024 * 4]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buffer);
    const reader = &stdin_reader.interface;

    var stdout_buffer: [1024 * 4]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    const lang = ts_bash.getLang();
    defer lang.destroy();

    const parser = ts.Parser.create();
    defer parser.destroy();
    try parser.setLanguage(lang);

    var handler = Handler.init(init.gpa, lang, parser, commands);
    defer handler.deinit(init.gpa);

    try server.start(init.gpa, init.arena, &handler, reader, writer);
}

test {
    std.testing.refAllDecls(@This());
}
