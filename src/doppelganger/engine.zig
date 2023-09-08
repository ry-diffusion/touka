const std = @import("std");

pub const c = @cImport({
    @cDefine("_NO_CRT_STDIO_INLINE", "1");

    @cInclude("libtcc.h");
});

pub const Error = error{ TccInitError, TccCompileError, RunFailed };

pub const State = struct {
    ptr: *c.TCCState,
    pub fn init() !State {
        var s = State{ .ptr = c.tcc_new() orelse {
            return Error.TccCompileError;
        } };

        _ = c.tcc_set_output_type(s.ptr, c.TCC_OUTPUT_MEMORY);
        _ = c.tcc_add_file(s.ptr, "/usr/lib/libc.so");

        return s;
    }

    pub fn compile(self: *@This(), source: [:0]const u8) !void {
        if (c.tcc_compile_string(self.ptr, source) == -1) {
            return Error.TccCompileError;
        }
    }

    pub fn run(self: *@This()) !void {
        if (c.tcc_run(self.ptr, 0, null) != 0) {
            return Error.RunFailed;
        }
    }

    pub fn load(self: *@This(), name: []const u8, func: *const anyopaque) !void {
        var c_fact_var = @as(?*anyopaque, @ptrFromInt(@intFromPtr(func)));

        _ = c.tcc_add_symbol(self.ptr, @ptrCast(name), c_fact_var);
    }
};
