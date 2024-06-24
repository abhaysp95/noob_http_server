const std = @import("std");
const net = std.net;
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
const debug = std.debug.print;
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
    const resp = try make_response(&req, allocator);
    try send_resp(&connection, &resp);
}

fn parse_request(conn: *const Connection, allocator: std.mem.Allocator) !Request {
    var buf: [1024]u8 = undefined;
    const buf_len = try conn.stream.read(&buf);

    var cursor = std.mem.indexOf(u8, &buf, "\r\n");
    const status = try allocator.dupe(u8, buf[0..cursor.?]);
    cursor.? += 1;

    var headers = HashMap.init(allocator);

    var header_iter = std.mem.splitSequence(u8, buf[cursor.?..], "\r\n");
    while (header_iter.next()) |header| {
        if (header.len == 0) { // end of headers
            cursor.? += 2; // skip past CRLF
            break;
        }
        const colon_idx = std.mem.indexOf(u8, header, ": ");
        const key = try allocator.dupe(u8, header[0..colon_idx.?]);
        const value = try allocator.dupe(u8, header[colon_idx.? + 2 ..]);
        try headers.put(key, value);
        cursor.? += header.len + 2;
    }

    var body: ?[]u8 = null;
    if (buf_len > cursor.? + 1) {
        body = try allocator.dupe(u8, buf[cursor.?..buf_len]);
    }

    return .{
        .status = status,
        .headers = headers,
        .body = body,
    };
}

fn make_response(req: *const Request, allocator: std.mem.Allocator) !Response {
    var req_status_iter = std.mem.splitSequence(u8, req.status, " ");
    _ = req_status_iter.next(); // no need for req HTTP verb
    const endpoint = req_status_iter.next().?;

    var headers = HashMap.init(allocator);
    if (std.mem.eql(u8, endpoint, "/")) {
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "0", .{}));
        return .{
            .status = "HTTP/1.1 200 OK\r\n\r\n",
            .headers = headers,
            .body = null,
        };
    } else if (std.mem.eql(u8, endpoint, "/user-agent")) {
        try headers.put("Content-Type", "text/plain");
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{req.headers.?.get("User-Agent").?.len}));
        return .{
            .status = "HTTP/1.1 200 OK\r\n",
            .headers = headers,
            .body = try std.fmt.allocPrint(allocator, "{s}", .{req.headers.?.get("User-Agent").?}),
        };
    } else if (!std.mem.startsWith(u8, endpoint, "/echo")) {
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "0", .{}));
        return .{
            .status = "HTTP/1.1 404 Not Found\r\n\r\n",
            .headers = headers,
            .body = null,
        };
    } else {
        // split to get endpoint heirarchy
        var target_level_iter = std.mem.tokenizeSequence(u8, endpoint, "/");
        var resource: []const u8 = undefined;
        while (target_level_iter.next()) |res| {
            resource = res;
        }

        try headers.put("Content-Type", "text/plain");
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{resource.len}));
        return .{
            .status = "HTTP/1.1 200 OK\r\n",
            .headers = headers,
            .body = try std.fmt.allocPrint(allocator, "{s}", .{resource}),
        };
    }
}

fn send_resp(conn: *const Connection, resp: *const Response) !void {
    const writer = conn.stream.writer();
    const write_len = try writer.write(resp.status);
    if (write_len < resp.status.len) {
        // TODO: error handling here
    }

    if (resp.headers) |headers| {
        var header_iter = headers.iterator();
        while (header_iter.next()) |entry| {
            try writer.print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        _ = try writer.write("\r\n"); // mark ending of headers
    }

    if (resp.body) |body| {
        try writer.writeAll(body);
    }
}
