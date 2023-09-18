const std = @import("std");
const json = std.json;
const fs = std.fs;
const AstReader = @import("reader.zig").AstReader;
const dpplgngr = @import("doppelganger/generator.zig");
const engine = @import("doppelganger/engine.zig");
const c = @cImport({
    @cInclude("malloc.h");
});

var lastMemoryUsage: i64 = 0;

inline fn getUsedBytes() u64 {
    var info = c.mallinfo2();
    const used = info.uordblks + info.hblkhd;
    return used;
}

pub const std_options = struct {
    pub const logFn = logger;
};

pub fn logger(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const used = @as(i64, @intCast(getUsedBytes()));
    const scope_prefix = switch (scope) {
        std.log.default_log_scope => "global",
        else => @tagName(scope),
    };

    var mark: u8 = '=';

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    var diff: i64 = used - lastMemoryUsage;

    if (used > lastMemoryUsage) {
        mark = '+';
    } else {
        mark = '-';
    }

    nosuspend stderr.print("[ {d:>10}B ({d:>8}B) ] {s:>7} ({s:<16}) ", .{ used, diff, level.asText(), scope_prefix }) catch return;
    lastMemoryUsage = used;
    nosuspend stderr.print(format ++ "\n", args) catch return;
}

pub fn main() !void {
    const gpa = std.heap.c_allocator;
    defer std.log.info("program finished.", .{});

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

    var generator = try dpplgngr.Generator.init(gpa);
    defer generator.deinit();

    _ = try AstReader.parseEntire(gpa, &generator, reader);

    var timer = try std.time.Timer.start();
    try generator.generate();
    const elapsed = timer.read();
    std.log.debug("gen file: {} ms ({} μs)", .{ elapsed / 1000 / 1000, elapsed / 1000 });
}
