const std = @import("std");

pub const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");

    @cInclude("libtcc.h");
    @cInclude("stdio.h>");
});

pub const Error = error{ TccInitError, TccCompileFailed, RunFailed, UnableToInsertSymbol, SetOptionFailed, UnableToReallocate };
fn damn(fmt: [*:0]const u8, args: anytype) void {
    _ = @call(.auto, std.c.printf, .{fmt} ++ args);
}

pub const State = struct {
    compilerState: *c.TCCState,
    const Self = @This();
    const log = std.log.scoped(.engine);

    pub fn init() Error!State {
        var s = State{
            .compilerState = c.tcc_new() orelse {
                return Error.TccInitError;
            },
        };

        if (c.tcc_set_output_type(s.compilerState, c.TCC_OUTPUT_MEMORY) != 0)
            return Error.SetOptionFailed;

        return s;
    }

    pub fn compile(self: *Self, source: []const u8) !void {
        log.debug("compiling {s}", .{source});
        if (c.tcc_compile_string(self.compilerState, source.ptr) == -1) {
            return Error.TccCompileFailed;
        }
    }

    pub fn run(self: *Self) !void {
        if (c.tcc_run(self.compilerState, 0, null) != 0)
            return Error.RunFailed;
    }

    pub fn insertSymbol(self: *Self, name: []const u8, func: *const anyopaque) !void {
        log.debug("inserting symbol: {s}", .{
            @typeName(@TypeOf(func)),
        });
        var cFunc = @as(?*anyopaque, @ptrFromInt(@intFromPtr(func)));

        if (c.tcc_add_symbol(self.compilerState, @ptrCast(name), cFunc) != 0)
            return Error.UnableToInsertSymbol;
    }

    pub fn set(self: *Self, name: []const u8, value: []const u8) void {
        log.debug("setting symbol: {s} = {s}", .{ name, value });
        c.tcc_define_symbol(self.compilerState, @ptrCast(name), @ptrCast(value));
    }

    pub fn unset(self: *Self, name: []const u8) void {
        log.debug("unsetting symbol: {s}", .{name});
        c.tcc_undefine_symbol(self.compilerState, @ptrCast(name));
    }

    pub fn exchange(self: *Self) !void {
        const size = c.tcc_relocate(self.compilerState, null);
        if (size < 0)
            return Error.UnableToReallocate;

        if (c.tcc_relocate(self.compilerState, c.TCC_RELOCATE_AUTO) < 0)
            return Error.UnableToReallocate;
    }

    pub fn getSymbol(self: *Self, name: [:0]const u8, comptime T: type) ?*T {
        var func: ?*T = @ptrCast(c.tcc_get_symbol(self.compilerState, @ptrCast(name)));

        return func;
    }

    pub fn deinit(self: *Self) void {
        c.tcc_delete(self.compilerState);
    }
};
