const std = @import("std");

const json = std.json;
const testing = std.testing;
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const CommandHelp = std.StringHashMap([]const u8);

fn JsonlToMap(allocator: Allocator, reader: *Io.Reader) !CommandHelp {
    var map: CommandHelp = .init(allocator);
    var line = Io.Writer.Allocating.init(allocator);
    defer line.deinit();

    while (reader.streamDelimiter(&line.writer, '\n')) |_| {
        _ = reader.toss(1);
        const json_line = try json.parseFromSlice(json.Value, allocator, line.written(), .{ .allocate = .alloc_always });
        defer json_line.deinit();

        var iterator = json_line.value.object.iterator();
        while (iterator.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(key);
            const value = try allocator.dupe(u8, entry.value_ptr.*.string);
            errdefer allocator.free(value);

            try map.put(key, value);
        }

        line.clearRetainingCapacity();
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    return map;
}

pub fn generateCommandHelp(io: Io, gpa: Allocator, path: []const u8) !CommandHelp {
    const file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var buffer: [64]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    return try JsonlToMap(gpa, &file_reader.interface);
}

test {
    const allocator = testing.allocator;
    const json_lines =
        \\{"cl":"Usage: cl [-fFnr]\n control your own life"}
        \\{"pvts":"Usage: pvts [-gufFp]\n prevents artificially transferble diseases"}
        \\{"ram2":"Usage: ram2 [ammount] [-bkMGP]\n free memory"}
        \\{"hw2farm":"Usage: hw2farm [-vulw]\n teach you how to grow grass/chiken and stuff"}
        \\{"dopegen":"Usage: dopegen [-vufk]\n generates dopamine in your terminal"}
        \\
    ;

    var reader = Io.Reader.fixed(json_lines);
    var map = try JsonlToMap(allocator, &reader);
    defer {
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    try testing.expect(map.get("cl") != null);
    try testing.expect(map.get("hw2farm") != null);
    try testing.expect(map.get("dopegen") != null);
}
