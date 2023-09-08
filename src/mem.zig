const std = @import("std");

pub fn box(alloc: std.mem.Allocator, comptime T: type, props: anytype) !*T {
    const new = try alloc.create(T);
    new.* = props;
    return new;
}
