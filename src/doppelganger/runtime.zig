const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const Tuple = std.meta.Tuple;

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    sourceName: ?[]u8 = null,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,

    const log = std.log.scoped(.doppelganger);
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        var rt = Runtime{
            .alloc = alloc,
            .engine = try engine.State.init(),
            .nuclearFlags = t.NuclearFlags.empty(),
        };

        rt.engine.set("DOPPELGANGER_SOURCE_NAME", "<nofile>");
        return rt;
    }

    pub fn setSourceName(self: *Self, to: t.String) !void {
        self.sourceName = try self.alloc.alloc(u8, to.len);
        @memcpy(self.sourceName.?, to);

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

    pub fn pushRoot(self: *Self, term: spec.Term) !void {
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.debug("NuclearFlags: noop marked.", .{});
            return;
        }

        switch (term) {
            .let => |let| {
                showInstropectLog(let);
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
