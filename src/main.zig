const std = @import("std");
const http = @import("./lib.zig");
const net = std.net;
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
const ThreadPool = std.Thread.Pool;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const debug = std.debug.print;
const stdout = std.io.getStdOut().writer();

fn sigint_handler(signum: i32) callconv(.C) void {
    debug("\nCaught the signal {d}. Exiting gracefully...\n\n", .{signum});
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

const THREAD_COUNT = 7;

fn handle_connection(connection: Connection, allocator: std.mem.Allocator) void {
    const req = http.parse_request(&connection, allocator) catch |err| {
        debug("{}\n", .{err});
        return handle_error(&connection);
    };
    handle_endpoints(&connection, &req, allocator) catch |err| {
        debug("{}\n", .{err});
        return handle_error(&connection);
    };
}

pub fn main() !void {
    const allocator = arena.allocator();
    defer arena.deinit();

    // standalone thread for signal handling
    _ = try std.Thread.spawn(.{}, register_signal, .{});

    var pool: ThreadPool = undefined;
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = THREAD_COUNT,
    });
    errdefer pool.deinit();
    defer pool.deinit();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });

    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();
        try stdout.print("client connected!\n", .{});
        try pool.spawn(handle_connection, .{ connection, allocator });
    }
}

fn handle_endpoints(conn: *const Connection, req: *const http.Request, allocator: std.mem.Allocator) !void {
    var req_status_iter = std.mem.splitSequence(u8, req.status, " ");
    _ = req_status_iter.next(); // no need for req HTTP verb
    const endpoint = req_status_iter.next().?;

    var response: http.Response = undefined;
    var headers = HashMap.init(allocator);
    if (std.mem.eql(u8, endpoint, "/")) {
        try headers.put("Content-Length", "0");
        response = http.Response.ok(headers);
    } else if (std.mem.eql(u8, endpoint, "/user-agent")) {
        try headers.put("Content-Type", "text/plain");
        try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{req.headers.?.get("User-Agent").?.len}));
        response = http.Response{
            .status = "HTTP/1.1 200 OK\r\n",
            .headers = headers,
            .body = try std.fmt.allocPrint(allocator, "{s}", .{req.headers.?.get("User-Agent").?}),
        };
    } else if (std.mem.startsWith(u8, endpoint, "/files/")) {
        var target_iter = std.mem.tokenizeSequence(u8, endpoint, "/");
        var resource: []const u8 = undefined;
        while (target_iter.next()) |res| {
            resource = res;
        }
        if (std.mem.eql(u8, resource, "non_existant_file")) {
            try headers.put("Content-Length", "0");
            response = http.Response.not_found(headers);
        } else {
            var filename_buf: [std.posix.PATH_MAX]u8 = undefined;
            @memset(&filename_buf, 0);
            const filepath = try std.fmt.bufPrint(&filename_buf, "/tmp/{s}", .{endpoint[7..]});
            var file = try std.fs.openFileAbsolute(filepath, .{});
            const file_size = (try file.stat()).size;
            if (file_size > 1024) { // dont't want to read big file, right now this is just demo
                return error.FileSizeTooLarge;
            }
            const content = try allocator.alloc(u8, file_size);
            _ = try file.readAll(content);

            try headers.put("Content-Type", "application/octet-stream");
            try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{file_size}));

            response = http.Response{
                .status = "HTTP/1.1 200 OK\r\n",
                .headers = headers,
                .body = content,
            };
        }
    } else if (std.mem.startsWith(u8, endpoint, "/echo")) {
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
        try headers.put("Content-Length", "0");
        response = http.Response.not_found(headers);
    }

    try response.send(conn.stream.writer());
}

fn handle_error(conn: *const Connection) void {
    conn.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n") catch return;
}
