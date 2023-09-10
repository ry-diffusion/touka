const std = @import("std");

pub const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");

    @cInclude("libtcc.h");
});

pub const Error = error{ TccInitError, TccCompileFailed, RunFailed, UnableToInsertSymbol, SetOptionFailed, UnableToReallocate };

pub const State = struct {
    compilerState: *c.TCCState,

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

    pub fn compile(self: *@This(), source: [:0]const u8) !void {
        if (c.tcc_compile_string(self.compilerState, source) == -1) {
            return Error.TccCompileFailed;
        }
    }

    pub fn run(self: *@This()) !void {
        if (c.tcc_run(self.compilerState, 0, null) != 0)
            return Error.RunFailed;
    }

    pub fn insertSymbol(self: *@This(), name: []const u8, func: *const anyopaque) !void {
        var cFunc = @as(?*anyopaque, @ptrFromInt(@intFromPtr(func)));

        if (c.tcc_add_symbol(self.compilerState, @ptrCast(name), cFunc) != 0)
            return Error.UnableToInsertSymbol;
    }

    pub fn set(self: *@This(), name: []const u8, value: []const u8) void {
        c.tcc_define_symbol(self.compilerState, @ptrCast(name), @ptrCast(value));
    }

    pub fn unset(self: *@This(), name: []const u8) void {
        c.tcc_undefine_symbol(self.compilerState, @ptrCast(name));
    }

    pub fn exchange(self: *@This()) !void {
        const size = c.tcc_relocate(self.compilerState, null);
        if (size < 0)
            return Error.UnableToReallocate;

        if (c.tcc_relocate(self.compilerState, c.TCC_RELOCATE_AUTO) < 0)
            return Error.UnableToReallocate;
    }

    pub fn getSymbol(self: *@This(), name: [:0]const u8, comptime T: type) ?*T {
        var func: ?*T = @ptrCast(c.tcc_get_symbol(self.compilerState, @ptrCast(name)));

        return func;
    }

    pub fn deinit(self: *@This()) void {
        c.tcc_delete(self.compilerState);
    }
};
