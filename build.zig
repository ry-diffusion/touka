const std = @import("std");
fn iterateFiles(b: *std.build.Builder, path: []const u8) !std.ArrayList([]const u8) {
    var files = std.ArrayList([]const u8).init(b.allocator);
    var dir = try std.fs.cwd().openIterableDir(path, .{});
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    var out: [256]u8 = undefined;
    const exclude_files: []const []const u8 = &.{ "ex1.c", "ex2.c", "ex3.c", "ex4.c", "ex5.c", "hello_dll.c", "dll.c", "fib.c", "dllcrt1.c", "dllmain.c", "wincrt1.c", "hello_win.c", "tiny_impdef.c" };
    const allowed_exts: []const []const u8 = &.{".c"};
    while (try walker.next()) |entry| {
        const ext = std.fs.path.extension(entry.basename);
        const include_file = for (allowed_exts) |e| {
            if (std.mem.eql(u8, ext, e))
                break true;
        } else false;
        if (include_file) {
            const exclude_file = for (exclude_files) |e| {
                if (std.mem.eql(u8, entry.basename, e))
                    break true;
            } else false;
            if (!exclude_file) {
                const file = try std.fmt.bufPrint(&out, ("{s}/{s}"), .{ path, entry.path });
                try files.append(b.dupe(file));
            }
        }
    }
    return files;
}
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    var tccPlat = [_:0]u8{undefined} ** 64;

    switch (b.host.target.cpu.arch) {
        .x86_64 => std.mem.copyForwards(u8, &tccPlat, "-DTCC_TARGET_X86_64"),
        .x86 => std.mem.copyForwards(u8, &tccPlat, "-DTCC_TARGET_I386"),
        .arm => std.mem.copyForwards(u8, &tccPlat, "-DTCC_TARGET_ARM"),
        else => std.debug.panic("incompatible platform! only x86_(64) and arm are supported.", .{}),
    }

    const tcc = b.addStaticLibrary(.{ .name = "tcc", .target = target, .optimize = optimize });
    tcc.addIncludePath(std.build.LazyPath.relative("./tcc"));
    tcc.addCSourceFile(.{
        .file = std.build.LazyPath.relative("./tcc/libtcc.c"),
        .flags = &[_][]const u8{
            &tccPlat,
            "-DCONFIG_TCC_STATIC",
            "-fno-strict-aliasing",
            "-fno-sanitize=undefined",
            "-Wno-pointer-sign",
        },
    });

    tcc.linkLibC();

    const exe = b.addExecutable(.{
        .name = "touka",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(tcc);
    // exe.step.dependOn(&tcc.step);
    exe.addIncludePath(std.build.LazyPath.relative("./tcc"));
    // exe.addObjectFile(std.build.LazyPath.relative("./tcc/libtcc.a"));
    exe.linkSystemLibrary("libuv");

    b.installLibFile("./tcc/libtcc.a", "libtcc1.a");
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addIncludePath(std.build.LazyPath.relative("./tcc"));
    unit_tests.linkLibrary(tcc);
    // unit_tests.addObjectFile(std.build.LazyPath.relative("./tcc/libtcc.a"));
    // unit_tests.addIncludePath(.{ .path = "/usr/include" });
    // unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
