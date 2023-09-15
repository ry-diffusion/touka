const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const libTouka = @embedFile("./touka.h");
const AutoHashMap = std.AutoHashMap;
const StringHM = std.StringHashMap;
const Tuple = std.meta.Tuple;

const EvaluationID = []u8;

pub const Phase = enum { Parsing, Generating };

pub const Generator = struct {
    const VariableMap = StringHM(t.String);

    alloc: std.mem.Allocator,
    phase: Phase,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,

    currentEvalId: t.Id,
    file: std.fs.File,
    output: std.io.BufferedWriter(4096, std.fs.File.Writer),

    const log = std.log.scoped(.doppelganger);
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Generator {
        const outputFile = try std.fs.cwd().createFile("DopplegangerOutput.c", .{});

        var rt = Generator{
            .alloc = alloc,
            .engine = try engine.State.init(),
            .nuclearFlags = t.NuclearFlags.empty(),
            .currentEvalId = 3,
            .output = std.io.bufferedWriter(outputFile.writer()),
            .file = outputFile,
            .phase = Phase.Parsing,
        };

        try outputFile.writeAll(libTouka);

        return rt;
    }

    pub fn setSourceName(self: *Self, to: t.String) !void {
        try std.fmt.format(self.output.writer(), "#define DOPPELGANGER_SOURCE_NAME \"{s}\"\n", .{to});
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

    inline fn append(self: *Self, fmt: t.String, args: anytype) !void {
        try std.fmt.format(self.output.writer(), fmt, args);
        _ = try self.output.write("\n");
    }

    pub fn generate(self: *Self) !void {
        try self.append("int main(void) {{", .{});
        try self.append("langLoop = tk_initLoop();", .{});

        defer self.append("}}", .{}) catch unreachable;
        defer self.append("return tk_run(langLoop, 0);", .{}) catch unreachable;
    }

    pub fn insert(self: *Self, term: spec.Term) !void {
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.warn("NuclearFlags: noop marked.", .{});
            return;
        }

        switch (term) {
            else => |ter| log.warn("unimplemented: {any}", .{ter}),
        }
    }

    pub fn deinit(self: *Self) void {
        self.engine.deinit();

        _ = self.output.flush() catch 0;
        self.file.close();
    }
};
