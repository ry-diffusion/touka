const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const inventory = @import("inventory.zig");
const Inventory = inventory.Inventory;
const Tuple = std.meta.Tuple;

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    sourceName: ?[]u8 = null,
    global: Inventory,
    const log = std.log.scoped(.doppelganger);

    pub fn init(alloc: std.mem.Allocator) Runtime {
        return Runtime{ .alloc = alloc, .global = Inventory.init(alloc) };
    }

    pub fn setSourceName(self: *@This(), to: t.String) !void {
        self.sourceName = try self.alloc.alloc(u8, to.len);
        std.mem.copy(u8, self.sourceName.?, to);
        log.info("set name to {s}", .{self.sourceName.?});
    }

    pub fn deinit(self: *@This()) void {
        self.global.deinit();
        if (self.sourceName) |name| {
            self.alloc.free(name);
        }
    }
};
