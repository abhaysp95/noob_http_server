const std = @import("std");
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
const debug = std.debug.print;

pub const Request = struct { status: []const u8, headers: ?HashMap, body: ?[]const u8 };
pub const Response = struct {
    status: []const u8,
    headers: ?HashMap,
    body: ?[]const u8,

    pub fn ok() Response {
        return .{
            .status = "HTTP/1.1 200 OK\r\n\r\n",
            .headers = null,
            .body = null,
        };
    }

    pub fn not_found() Response {
        return .{
            .status = "HTTP/1.1 404 Not Found\r\n\r\n",
            .headers = null,
            .body = null,
        };
    }

    pub fn send(self: *@This(), writer: std.net.Stream.Writer) !void {
        const write_len = try writer.write(self.status);
        if (write_len < self.status.len) {
            // TODO: error handling here
        }

        if (self.headers) |headers| {
            var header_iter = headers.iterator();
            while (header_iter.next()) |entry| {
                try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            _ = try writer.write("\r\n"); // mark ending of headers
        }

        if (self.body) |body| {
            try writer.writeAll(body);
        }
    }
};

const Verb = enum { GET, POST, PUT, DELETE, PATCH };

pub fn parse_request(conn: *const Connection, allocator: std.mem.Allocator) !Request {
    var buf: [1024]u8 = undefined;
    const buf_len = try conn.stream.read(&buf);

    var cursor = std.mem.indexOf(u8, &buf, "\r\n");
    const status = try allocator.dupe(u8, buf[0..cursor.?]);
    cursor.? += 1;

    var headers: ?HashMap = null;
    var body: ?[]u8 = null;
    if (buf_len > cursor.? + 3) { // check for \r\n\r\n
        headers = HashMap.init(allocator);

        var header_iter = std.mem.splitSequence(u8, buf[cursor.?..], "\r\n");
        while (header_iter.next()) |header| {
            if (header.len == 0) { // end of headers
                cursor.? += 2; // skip past CRLF
                break;
            }
            const colon_idx = std.mem.indexOf(u8, header, ": ");
            const key = try allocator.dupe(u8, header[0..colon_idx.?]);
            const value = try allocator.dupe(u8, header[colon_idx.? + 2 ..]);
            try headers.?.put(key, value);
            cursor.? += header.len + 2;
        }

        if (buf_len > cursor.? + 1) {
            body = try allocator.dupe(u8, buf[cursor.?..buf_len]);
        }
    }

    return .{
        .status = status,
        .headers = headers,
        .body = body,
    };
}
