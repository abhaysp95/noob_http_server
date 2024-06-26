const std = @import("std");
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
const debug = std.debug.print;

pub const Verb = enum { GET, POST, PUT, DELETE, PATCH };
pub const Encoding = enum { gzip };

pub const Request = struct { status: []const u8, headers: ?HashMap, body: ?[]const u8 };
pub const Response = struct {
    status: []const u8,
    headers: ?HashMap,
    body: ?[]const u8,

    pub fn success(success_code: u16, msg: []const u8, header: ?HashMap, allocator: std.mem.Allocator) !Response {
        // NOTE: 201 is not working with buf, but 200 and 404 below are working fine. Why ?
        const response = Response{
            .status = try std.fmt.allocPrint(allocator, "HTTP/1.1 {d} {s}\r\n", .{ success_code, msg }),
            .headers = header,
            .body = null,
        };

        debug("resp status line: {s}\n", .{response.status});
        debug("resp status line len: {d}\n", .{response.status.len});
        return response;
    }

    pub fn client_error(client_error_code: u16, msg: []const u8, header: ?HashMap) !Response {
        var buf: [127]u8 = undefined;
        @memset(&buf, 0);
        return .{
            .status = try std.fmt.bufPrint(&buf, "HTTP/1.1 {d} {s}\r\n", .{ client_error_code, msg }),
            .headers = header,
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
        }

        if (self.body) |body| {
            _ = try writer.write("\r\n"); // mark ending of headers
            try writer.writeAll(body);
        } else {
            _ = try writer.write("\r\n"); // mark ending of headers or statusline
        }
    }
};

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
            cursor.? += header.len + 2;

            const colon_idx = std.mem.indexOf(u8, header, ": ");
            const key = try allocator.dupe(u8, header[0..colon_idx.?]);
            const value = try allocator.dupe(u8, header[colon_idx.? + 2 ..]);

            // currently comma-seperated multiple encoding scheme supported
            // TODO: probably to added multiple header encoding too ie., pass multiple headers in request
            // which will have same key but different values
            // TODO: check whether this be done for what different types of headers
            if (std.mem.eql(u8, key, "Accept-Encoding")) {
                var encoding_str: ?[]u8 = null;
                var iter = std.mem.splitSequence(u8, value, ", ");
                while (iter.next()) |encoding| {
                    // if encoding is supported
                    if (null == std.meta.stringToEnum(Encoding, encoding)) {
                        continue;
                    }
                    if (null == encoding_str) {
                        encoding_str = try allocator.dupe(u8, encoding);
                    } else {
                        const old_len = encoding_str.?.len;
                        encoding_str = try allocator.realloc(encoding_str.?, old_len + encoding.len + 2);
                        std.mem.copyForwards(u8, encoding_str.?[old_len..], ", ");
                        std.mem.copyForwards(u8, encoding_str.?[old_len + 2 ..], encoding);
                    }
                }
                if (null != encoding_str) {
                    if (std.mem.endsWith(u8, encoding_str.?, ", ")) {
                        encoding_str = try allocator.realloc(encoding_str.?, encoding_str.?.len - 2);
                    }
                    try headers.?.put(key, encoding_str.?);
                }
            } else {
                try headers.?.put(key, value);
            }
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
