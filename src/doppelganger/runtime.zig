const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const crt1 = @embedFile("./crt1.h");
const Tuple = std.meta.Tuple;
const jitKinds = enum {
    Int32,
    Boolean,
    Str,

    pub fn toString(self: @This()) []const u8 {
        return switch (self) {
            .Int32 => "int",
            .Str => "char*",
            .Boolean => "unsigned char",
        };
    }
};

const jitTrue = "E_1";
const jitFalse = "E_2";

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    sourceName: ?[]u8 = null,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,
    evalIdBuffer: [16]u8,
    currentEvalId: t.Id,

    const log = std.log.scoped(.doppelganger);
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        var rt = Runtime{
            .alloc = alloc,
            .engine = try engine.State.init(),
            .nuclearFlags = t.NuclearFlags.empty(),
            .currentEvalId = 3,
            .evalIdBuffer = std.mem.zeroes([16]u8),
        };

        rt.engine.set("DOPPELGANGER_SOURCE_NAME", "<nofile>");

        try rt.engine.compile(crt1);

        return rt;
    }

    pub fn setSourceName(self: *Self, to: t.String) !void {
        self.sourceName = try self.alloc.alloc(u8, to.len);
        @memcpy(self.sourceName.?, to);
        self.engine.unset("DOPPELGANGER_SOURCE_NAME");
        self.engine.set("DOPPELGANGER_SOURCE_NAME", to);
        log.info("set name to {s}", .{self.sourceName.?});
    }

    inline fn showInstropectLog(item: anytype) void {
        log.debug("converting {s} at {s}:{}:{}", .{
            @typeName(@TypeOf(item)),
            item.location.filename,
            item.location.start,
            item.location.end,
        });
    }

    fn insertEvaluation(self: *Self, term: spec.Term) ![16]u8 {
        _ = std.fmt.bufPrint(&self.evalIdBuffer, "E_{:0>14}", .{self.currentEvalId}) catch unreachable;
        self.currentEvalId += 1;

        switch (term) {
            .str => |v| {
                showInstropectLog(v);
                const it = try std.fmt.allocPrintZ(
                    self.alloc,
                    "const {s} {s} = \"{s}\";",
                    .{
                        jitKinds.Str.toString(),
                        self.evalIdBuffer,
                        v.value,
                    },
                );

                defer self.alloc.free(it);
                try self.engine.compile(it);
            },

            .int => |i| {
                showInstropectLog(i);
                const it = try std.fmt.allocPrintZ(
                    self.alloc,
                    "const {s} {s} = {};",
                    .{
                        jitKinds.Int32.toString(),
                        self.evalIdBuffer,
                        i.value,
                    },
                );

                defer self.alloc.free(it);
                try self.engine.compile(it);
            },

            .tuple => |v| {
                showInstropectLog(v);
                const first = try self.insertEvaluation(v.first);
                const second = try self.insertEvaluation(v.second);

                log.debug("creating tuple ({s}, {s})", .{ first, second });
            },

            else => |v| {
                log.warn("unimplemented {any}", .{v});
            },
        }

        return self.evalIdBuffer;
    }

    pub fn pushRoot(self: *Self, term: spec.Term) !void {
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.debug("NuclearFlags: noop marked.", .{});
            return;
        }

        switch (term) {
            .let => |let| {
                showInstropectLog(let);
                const valueId = try self.insertEvaluation(let.value);
                _ = valueId;
                log.debug("Loading variable: {s}", .{let.name.text});
            },

            .boolean => |it| {
                _ = it;
            },

            else => |it| {
                log.err("unimplemented: {s}", .{@tagName(it)});
            },
        }
    }

    pub fn deinit(self: *Self) void {
        self.engine.deinit();

        if (self.sourceName) |name| {
            self.alloc.free(name);
        }
    }
};
