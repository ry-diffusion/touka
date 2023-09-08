const engine = @import("doppelganger/engine.zig");
const std = @import("std");

const Hey = extern struct {
    ok: bool,
    zigString: [*c]u8,
};

fn show(a: [*c]u8) callconv(.C) void {
    const z: [:0]u8 = std.mem.span(a);
    std.debug.print("{s}\n", .{z});
}

test "Doppelgänger engine - basic compile and run" {
    var jit = try engine.State.init(std.testing.allocator);
    defer jit.deinit();

    try jit.compile(
        \\ int main(void)
        \\ {
        \\  return 0;
        \\}
    );

    try jit.run();
}

test "Doppelgänger engine - use zig native interfaces" {
    var jit = try engine.State.init(std.testing.allocator);
    defer jit.deinit();
    var oi = "oi";
    var hey = Hey{ .ok = false, .zigString = @constCast(oi) };

    try jit.insertSymbol("printString", show);

    try jit.compile(
        \\ struct ZigData {
        \\  int ok;
        \\  char* data;
        \\ };
        \\
        \\ int AppInit(struct ZigData* zd)
        \\ {
        \\     zd->ok = 1;
        \\     printString(zd->data);
        \\ }
    );

    try jit.exchange();

    const symbol = jit.getSymbol("AppInit", fn (*Hey) void);
    symbol.?(&hey);

    std.debug.print("{any}", .{hey});
}
