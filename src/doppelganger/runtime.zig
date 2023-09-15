const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const libTouka = @embedFile("./touka.h");
const AutoHashMap = std.AutoHashMap;
const Tuple = std.meta.Tuple;

const EvaluationID = []u8;

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,

    buf: [16]u8,
    currentEvalId: t.Id,
    outputFile: std.fs.File,

    outputWriter: std.io.BufferedWriter(4096, std.fs.File.Writer),

    const log = std.log.scoped(.doppelganger);
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        const outputFile = try std.fs.cwd().createFile("DopplegangerOutput.c", .{});
        var rt = Runtime{
            .alloc = alloc,
            .engine = try engine.State.init(),
            .nuclearFlags = t.NuclearFlags.empty(),
            .currentEvalId = 3,
            .buf = std.mem.zeroes([16]u8),
            .outputWriter = std.io.bufferedWriter(outputFile.writer()),
            .outputFile = outputFile,
        };

        try outputFile.writeAll(libTouka);

        return rt;
    }

    pub fn setSourceName(self: *Self, to: t.String) !void {
        try std.fmt.format(self.outputWriter.writer(), "#define DOPPELGANGER_SOURCE_NAME \"{s}\"\n", .{to});
        log.info("set name to {s}", .{to});
    }

    inline fn showInstropectLog(item: anytype) void {
        log.debug("converting {s} at {s}:{}:{}", .{
            @typeName(@TypeOf(item)),
            item.location.filename,
            item.location.start,
            item.location.end,
        });
    }

    pub fn insert(self: *Self, term: spec.Term) !void {
        _ = term;
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.debug("NuclearFlags: noop marked.", .{});
            return;
        }
    }

    pub fn deinit(self: *Self) void {
        self.engine.deinit();

        _ = self.outputWriter.flush() catch 0;
        self.outputFile.close();
    }
};
