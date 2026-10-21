const std = @import("std");

const Io = std.Io;

pub const Logger = @This();

file: ?Io.File = null,

pub fn init() @This() {
    return .{};
}

pub fn deinit(self: *@This(), io: Io) void {
    if (self.file) |file| {
        file.close(io);
        self.file = null;
    }
    self.* = undefined;
}

pub fn log(
    self: @This(),
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime fmt: []const u8,
    args: anytype,
) void {
    _ = scope;
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [1024 * 8]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    writer.print("[bash_ls] {s}: ", .{level.asText()}) catch {};
    writer.print(fmt, args) catch {};
    writer.writeByte('\n') catch {};

    if (self.file) |file| {
        const is_locked = if (file.lock(io, .exclusive)) |_| true else |_| false;
        defer if (is_locked) file.unlock(io);
        if (file.length(io)) |length| {
            file.writePositionalAll(io, writer.buffered(), length) catch {};
        } else |_| {
            file.writeStreamingAll(io, writer.buffered()) catch {};
        }
    }
}

pub fn setLogFile(self: *@This(), io: Io, log_file_path: []const u8) void {
    self.file = Io.Dir.cwd().createFile(io, log_file_path, .{ .truncate = false }) catch null;
}
