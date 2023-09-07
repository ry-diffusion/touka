const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const Tuple = std.meta.Tuple;

pub const Value = union(enum) {
    bool: bool,
    string: t.String,
    number: i32,
    closure: void,
    tuple: Tuple(.{ Value, Value }),
};

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    sourceName: ?[]u8 = null,
    const log = std.log.scoped(.doppelganger);

    pub fn init(alloc: std.mem.Allocator) Runtime {
        return Runtime{ .alloc = alloc };
    }

    pub fn setSourceName(self: *@This(), to: t.String) !void {
        self.sourceName = try self.alloc.alloc(u8, to.len);
        std.mem.copy(u8, self.sourceName.?, to);
        log.info("set name to {s}", .{self.sourceName.?});
    }

    pub fn deinit(self: *@This()) void {
        if (self.sourceName) |name| {
            self.alloc.free(name);
        }
    }
};
