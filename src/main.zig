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
    var req_target = iter.next().?;
    req_target = req_target[1..];

    // writer status line
    _ = try conn_writer.write("HTTP/1.1 200 OK\r\n");
    _ = try conn_writer.write("Content-Type: text/plain\r\n");
    _ = try conn_writer.print("Content-Length: {d}\r\n\r\n", .{req_target.len});
    _ = try conn_writer.print("{s}\r\n", .{req_target});
}
