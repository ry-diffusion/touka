const std = @import("std");
const json = std.json;
const fs = std.fs;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer std.debug.assert(general_purpose_allocator.deinit() == .ok);

    var argv = std.process.args();
    _ = argv.next();

    const fileName = argv.next() orelse {
        std.debug.panic("I need a json file bro.", .{});
    };

    const absolutePath = try std.fs.realpathAlloc(gpa, fileName);
    defer gpa.free(absolutePath);

    const inputFile = try fs.openFileAbsolute(absolutePath, .{ .mode = std.fs.File.OpenMode.read_only });
    defer inputFile.close();

    _ = json.reader(gpa, inputFile);
}
