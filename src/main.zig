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

    var conn_reader = connection.stream.reader();
    var conn_writer = connection.stream.writer();

    var buf: [1024]u8 = undefined;
    _ = try conn_reader.read(&buf);

    var crlf_iter = std.mem.splitSequence(u8, &buf, "\r\n");
    const req_line = crlf_iter.next().?;

    var iter = std.mem.splitSequence(u8, req_line, " ");
    _ = iter.next(); // no need for HTTP method
    const req_target = iter.next().?;

    if (req_target.len > 1) {
        // ignoring the len of buf written
        _ = try conn_writer.write("HTTP/1.1 404 Not Found\r\n\r\n");
    } else {
        // ignoring the len of buf written
        _ = try conn_writer.write("HTTP/1.1 200 OK\r\n\r\n");
    }
}
