const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const t = @import("types.zig");
const Tuple = std.meta.Tuple;

pub const Value = union(enum) {
    bool: bool,
    string: t.String,
    number: i32,
    closure: void,
    tuple: struct { first: *Value, second: *Value },
};

pub const Object = struct {
    id: t.Id,
    inner: Value,
};

pub const Inventory = struct {
    alloc: Allocator,
    arena: ArenaAllocator,
    children: std.ArrayList(*Object),

    pub fn push(self: *@This(), value: Value) t.Id {
        _ = value;
        self.alloc.create(Object);
    }

    pub fn init(parentAlloc: Allocator) Inventory {
        var arena = ArenaAllocator.init(parentAlloc);
        var alloc = arena.allocator();

        return Inventory{
            .alloc = alloc,
            .arena = arena,
            .children = std.ArrayList(*Object).init(alloc),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.children.deinit();
        self.arena.deinit();
    }
};
