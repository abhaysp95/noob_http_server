const std = @import("std");

pub fn read_file(dir_path: []const u8, file_path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch |err| {
        if (std.fs.File.OpenError.FileNotFound == err) {
            return error.FileNotFound;
        }
        return err;
    };
    var file = dir.openFile(file_path, .{}) catch |err| {
        if (std.fs.File.OpenError.FileNotFound == err) {
            return error.FileNotFound;
        }
        return err;
    };
    defer dir.close();
    defer file.close();
    if ((try file.stat()).size > 1024) {
        return error.FileSizeTooLarge;
    }

    return file.readToEndAlloc(allocator, @as(usize, 0) -% 1);
}

pub fn write_file(dir_path: []const u8, file_path: []const u8, content: []const u8) !void {
    var dir = std.fs.openDirAbsolute(dir_path, .{}) catch |err| {
        if (std.fs.File.OpenError.FileNotFound == err) {
            return error.FileNotFound;
        }
        return err;
    };
    if (dir_path.len + file_path.len + 1 > std.posix.PATH_MAX) {
        return error.FileNameTooLarge;
    }
    var file = dir.createFile(file_path, .{ .exclusive = false, .truncate = true }) catch |err| {
        if (std.fs.File.OpenError.PathAlreadyExists == err or std.fs.File.OpenError.AccessDenied == err) {
            return error.FileCreationFailed;
        }
        return err;
    };
    defer dir.close();
    defer file.close();

    file.writeAll(content) catch |err| return err;
}
