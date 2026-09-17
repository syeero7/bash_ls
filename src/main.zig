const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");

pub fn main(init: std.process.Init) !void {
    _ = init;
    _ = jsonrpc;
}

test {
    std.testing.refAllDecls(@This());
}
