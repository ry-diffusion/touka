const engine = @import("doppelganger/engine.zig");
const std = @import("std");

var output: [32]u8 = [_]u8{0} ** 32;

const Hey = extern struct {
    ok: bool,
    zigString: [*c]u8,
    buffer: *[32]u8,
};

fn copy(b: [*c]u8, a: [*c]u8, size: usize) callconv(.C) void {
    for (0..size) |i| {
        b[i] = a[i];
    }
}

test "Doppelgänger engine - basic compile and run" {
    var jit = try engine.State.init();
    defer jit.deinit();

    try jit.compile(
        \\ void _start(void)
        \\ {
        \\}
    );

    try jit.run();
}

test "Doppelgänger engine - use zig native interfaces" {
    var jit = try engine.State.init();
    defer jit.deinit();
    var oi = "oi";
    var hey = Hey{
        .ok = false,
        .zigString = @constCast(oi),
        .buffer = &output,
    };

    try jit.insertSymbol("copy", copy);

    try jit.compile(
        \\ extern void copy(char*, char*, unsigned int sz);
        \\ struct ZigData {
        \\  int ok;
        \\  char* data, *buffer;
        \\ };
        \\
        \\ void AppInit(struct ZigData* zd)
        \\ {
        \\     zd->ok = 1;
        \\     copy(zd->buffer, zd->data, 2);
        \\ }
    );

    try jit.exchange();

    const symbol = jit.getSymbol("AppInit", fn (*Hey) void);
    symbol.?(&hey);

    std.debug.assert(hey.ok == true);
    std.debug.assert(std.mem.eql(u8, output[0..2], "oi"));
}
