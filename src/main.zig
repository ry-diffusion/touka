const std = @import("std");
const json = std.json;
const fs = std.fs;
const ast = @import("ast.zig");
const AstReader = @import("reader.zig").AstReader;
const dpplgngr = @import("doppelganger/runtime.zig");
const engine = @import("doppelganger/engine.zig");

fn printMemoryInformations() void {
    const c = @cImport({
        @cInclude("malloc.h");
    });

    var info = c.mallinfo2();
    const used = info.uordblks + info.hblkhd;

    std.debug.print("debug(memoryInfo): used {d} bytes\n", .{used});
}

pub fn main() !void {
    const gpa = std.heap.c_allocator;
    defer printMemoryInformations();

    var argv = std.process.args();
    _ = argv.next();

    const fileName = argv.next() orelse {
        std.debug.panic("I need a json file bro.", .{});
    };

    const absolutePath = try std.fs.realpathAlloc(gpa, fileName);

    const inputFile = try fs.openFileAbsolute(absolutePath, .{ .mode = std.fs.File.OpenMode.read_only });
    defer inputFile.close();
    gpa.free(absolutePath);

    var reader = inputFile.reader();

    var runtime = try dpplgngr.Runtime.init(gpa);
    defer runtime.deinit();

    _ = try AstReader.parseEntire(gpa, &runtime, reader);
}
