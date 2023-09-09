const std = @import("std");
const json = std.json;
const fs = std.fs;
const ast = @import("ast.zig");
const AstReader = @import("reader.zig").AstReader;
const dpplgngr = @import("doppelganger/runtime.zig");
const engine = @import("doppelganger/engine.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};

    // 640 KiB
    general_purpose_allocator.setRequestedMemoryLimit(640 * 1024);

    const gpa = general_purpose_allocator.allocator();
    defer std.debug.assert(general_purpose_allocator.deinit() == .ok);

    var argv = std.process.args();
    _ = argv.next();

    const fileName = argv.next() orelse {
        std.debug.panic("I need a json file bro.", .{});
    };

    const absolutePath = try std.fs.realpathAlloc(gpa, fileName);

    const inputFile = try fs.openFileAbsolute(absolutePath, .{ .mode = std.fs.File.OpenMode.read_only });
    defer inputFile.close();
    gpa.free(absolutePath);

    var runtime = try dpplgngr.Runtime.init(gpa);

    var reader = inputFile.reader();
    defer runtime.deinit();

    _ = try AstReader.parseEntire(gpa, &runtime, reader);

    std.log.info("requested {} bytes during execution.", .{general_purpose_allocator.total_requested_bytes});
}
