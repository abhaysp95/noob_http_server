const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var connection = try listener.accept();
    defer connection.stream.close();
    try stdout.print("client connected!", .{});

    var conn_writer = connection.stream.writer();

    // ignoring the len of buf written
    _ = try conn_writer.write("HTTP/1.1 200 OK\r\n\r\n");
}
