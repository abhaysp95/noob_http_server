const std = @import("std");
const http = @import("./lib.zig");
const net = std.net;
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const debug = std.debug.print;
const stdout = std.io.getStdOut().writer();

fn sigint_handler(signum: i32) callconv(.C) void {
    debug("Caught the signal {d}. Exiting gracefully...\n", .{signum});
    // do cleanup
    arena.deinit();

    std.process.exit(1);
}

fn register_signal() void {
    var sa = std.posix.Sigaction{
        .handler = .{
            .handler = sigint_handler,
        },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.INT, &sa, null) catch |err| {
        debug("registering signal handler failed: {}\n", .{err});
        std.process.exit(1);
    };

    while (true) {
        // .. wait indefinitely for signal
    }
}

pub fn main() !void {
    const allocator = arena.allocator();
    defer arena.deinit();

    _ = try std.Thread.spawn(.{}, register_signal, .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    var connection = try listener.accept();
    defer connection.stream.close();
    try stdout.print("client connected!\n", .{});

    const req = try http.parse_request(&connection, allocator);
    try handle_endpoints(&connection, &req, allocator);
}

fn handle_endpoints(conn: *const Connection, req: *const http.Request, allocator: std.mem.Allocator) !void {
    var req_status_iter = std.mem.splitSequence(u8, req.status, " ");
    _ = req_status_iter.next(); // no need for req HTTP verb
    const endpoint = req_status_iter.next().?;

    var response: http.Response = undefined;
    if (std.mem.eql(u8, endpoint, "/")) {
        response = http.Response.ok();
    } else if (std.mem.eql(u8, endpoint, "/user-agent")) {
        var headers = HashMap.init(allocator);
        try headers.put("Content-Type", "text/plain");
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{req.headers.?.get("User-Agent").?.len}));
        response = http.Response{
            .status = "HTTP/1.1 200 OK\r\n",
            .headers = headers,
            .body = try std.fmt.allocPrint(allocator, "{s}", .{req.headers.?.get("User-Agent").?}),
        };
    } else if (std.mem.startsWith(u8, endpoint, "/echo")) {
        var headers = HashMap.init(allocator);

        // split to get endpoint heirarchy
        var target_level_iter = std.mem.tokenizeSequence(u8, endpoint, "/");
        var resource: []const u8 = undefined;
        while (target_level_iter.next()) |res| {
            resource = res;
        }

        try headers.put("Content-Type", "text/plain");
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{resource.len}));
        response = http.Response{
            .status = "HTTP/1.1 200 OK\r\n",
            .headers = headers,
            .body = try std.fmt.allocPrint(allocator, "{s}", .{resource}),
        };
    } else {
        response = http.Response.not_found();
    }

    try response.send(conn.stream.writer());
}
