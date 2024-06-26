const std = @import("std");
const http = @import("./http.zig");
const util = @import("./util.zig");
const net = std.net;
const Connection = std.net.Server.Connection;
const HashMap = std.StringHashMap([]const u8);
const ThreadPool = std.Thread.Pool;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
const debug = std.debug.print;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

fn sigint_handler(signum: i32) callconv(.C) void {
    debug("\nCaught the signal {d}. Exiting gracefully...\n\n", .{signum});
    do_cleanup();

    std.process.exit(1);
}

fn do_cleanup() void {
    arena.deinit();
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
    const verb_status_line = req_status_iter.next().?; // no need for req HTTP verb
    const endpoint = req_status_iter.next().?;

    var response: http.Response = undefined;
    var headers = HashMap.init(allocator);

    if (std.mem.eql(u8, endpoint, "/")) {
        try headers.put("Content-Length", "0");
        response = try http.Response.success(200, "OK", headers, allocator);
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
        // read file and all
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);
        if (args.len < 3 or !std.mem.eql(u8, args[1], "--directory") or !std.mem.endsWith(u8, args[2], "/")) {
            try stderr.print("Directory name not provided.\nUsage: ./server --directory <path_to_file>\n", .{});
            handle_error(conn);
            do_cleanup();
            std.process.exit(1); // exiting because server needs to run again for this to pass
        }
        const directory_path = args[2];

        const verb = std.meta.stringToEnum(http.Verb, verb_status_line) orelse {
            return error.UnknownVerb;
        };
        switch (verb) {
            .GET => {
                const file_content = util.read_file(directory_path, resource, allocator) catch |err| {
                    if (error.FileNotFound == err) {
                        try headers.put("Content-Length", "0");
                        response = try http.Response.client_error(404, "Not Found", headers); // return 404
                        try response.send(conn.stream.writer());
                        return;
                    }
                    return err; // will return 500
                };
                try headers.put("Content-Type", "application/octet-stream");
                try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{file_content.len}));

                response = http.Response{
                    .status = "HTTP/1.1 200 OK\r\n",
                    .headers = headers,
                    .body = file_content,
                };
            },
            .POST => {
                if (null == req.body) {
                    return error.BodyNotFound;
                }
                // we don't have use for header as of now
                try util.write_file(directory_path, resource, req.body.?);
                try headers.put("Content-Length", "0");
                response = try http.Response.success(201, "Created", headers, allocator);
            },
            else => {},
        }
    } else if (std.mem.startsWith(u8, endpoint, "/echo")) {
        // split to get endpoint heirarchy
        var target_level_iter = std.mem.tokenizeSequence(u8, endpoint, "/");
        var resource: []const u8 = undefined;
        while (target_level_iter.next()) |res| {
            resource = res;
        }

        try headers.put("Content-Type", "text/plain");
        if (req.headers) |req_headers| {
            if (req_headers.get("Accept-Encoding")) |encoding| {
                try headers.put("Content-Encoding", encoding);
            }
        }

        const encoding = headers.get("Content-Encoding");
        var body: []u8 = undefined;
        if (resource.len != 0 and null != encoding and std.mem.containsAtLeast(u8, encoding.?, 1, "gzip")) {
            // currently only gzip compression is supported
            body = try util.gzip_compressed(resource, allocator);

            // TODO: the scope is this if-block thus defer freeing here will create problem
            // Fix this later
            // defer allocator.free(body);

            try headers.put("Content-Length", try std.fmt.allocPrint(allocator, "{d}", .{body.len}));
        } else {
            try headers.put("Content-Length", "0");
        }

        response = http.Response{
            .status = "HTTP/1.1 200 OK\r\n",
            .headers = headers,
            .body = body,
        };
    } else {
        try headers.put("Content-Length", "0");
        response = try http.Response.client_error(404, "Not Found", headers);
    }

    try response.send(conn.stream.writer());
}

fn handle_error(conn: *const Connection) void {
    conn.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n") catch return;
}
