const std = @import("std");
const net = std.net;
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
const stdout = std.io.getStdOut().writer();

const Request = struct { status: []const u8, headers: ?HashMap, body: ?[]const u8 };
const Response = struct { status: []const u8, headers: ?HashMap, body: ?[]const u8 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const allocator = arena.allocator();
    defer arena.deinit();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var connection = try listener.accept();
    defer connection.stream.close();
    try stdout.print("client connected!\n", .{});

    const req = try parse_request(&connection, allocator);
    try stdout.print("status: {s}\n", .{req.status});

    var header_iterator = req.headers.?.iterator();
    while (header_iterator.next()) |entry| {
        try stdout.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    if (req.body) |body| {
        try stdout.print("body: {s}\n", .{body});
    }

    _ = try connection.stream.write("HTTP/1.1 200 OK\r\n\r\n");
}

fn parse_request(conn: *const Connection, allocator: std.mem.Allocator) !Request {
    var buf: [1024]u8 = undefined;
    const buf_len = try conn.stream.readAll(&buf);

    var cursor = std.mem.indexOf(u8, &buf, "\r\n");
    const status = try allocator.alloc(u8, cursor.?);
    std.mem.copyForwards(u8, status, buf[0..cursor.?]);
    cursor.? += 1;

    var headers = HashMap.init(allocator);

    var header_iter = std.mem.splitSequence(u8, buf[cursor.?..], "\r\n");
    while (header_iter.next()) |header| {
        if (header.len == 0) { // end of headers
            cursor.? += 2; // skip past CRLF
            break;
        }
        const colon_idx = std.mem.indexOf(u8, header, ": ");
        try headers.put(header[0..colon_idx.?], header[colon_idx.? + 1 ..]);
        cursor.? += header.len + 2;
    }

    var body: ?[]u8 = null;
    if (buf_len > cursor.? + 1) {
        body = try allocator.alloc(u8, buf_len - cursor.?);
        std.mem.copyForwards(u8, body.?, buf[cursor.?..buf_len]);
    }

    return .{
        .status = status,
        .headers = headers,
        .body = body,
    };
}
