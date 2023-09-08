const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");

const Tuple = std.meta.Tuple;

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    sourceName: ?[]u8 = null,
    engine: engine.State,
    const log = std.log.scoped(.doppelganger);

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        return Runtime{
            .alloc = alloc,
            .engine = try engine.State.init(alloc),
        };
    }

    pub fn setSourceName(self: *@This(), to: t.String) !void {
        self.sourceName = try self.alloc.alloc(u8, to.len);
        self.engine.set("DOPPELGANGER_SOURCE_NAME", to);
        log.info("set name to {s}", .{self.sourceName.?});
    }

    pub fn deinit(self: *@This()) void {
        self.engine.deinit();
        if (self.sourceName) |name| {
            self.alloc.free(name);
        }
    }
};
