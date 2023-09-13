const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const crt1 = @embedFile("./crt1.h");
const AutoHashMap = std.AutoHashMap;
const Tuple = std.meta.Tuple;
const jitKinds = enum {
    Int32,
    Boolean,
    Str,
    Function,
    Tuple,

    pub fn toString(self: @This()) []const u8 {
        return switch (self) {
            .Int32 => "Num",
            .Str => "Str",
            .Tuple => "struct Tuple",
            .Boolean => "Boolean",
            .Function => "struct nUvWorkState *",
        };
    }
};

const TuplePrimitive = struct {
    first: jitKinds,
    second: jitKinds,
};

const jitTrue = "E_1";
const jitFalse = "E_2";

const EvaluationID = [16]u8;

pub const Runtime = struct {
    const Tuples = AutoHashMap(TuplePrimitive, EvaluationID);
    alloc: std.mem.Allocator,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,
    evalIdBuffer: EvaluationID,
    currentEvalId: t.Id,
    tuples: Tuples,
    outputFile: std.fs.File,
    outputWriter: std.io.BufferedWriter(4096, std.fs.File.Writer),

    const log = std.log.scoped(.doppelganger);
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Runtime {
        const outputFile = try std.fs.cwd().createFile("DopplegangerOutput.c", .{});
        var rt = Runtime{
            .alloc = alloc,
            .engine = try engine.State.init(),
            .nuclearFlags = t.NuclearFlags.empty(),
            .currentEvalId = 3,
            .evalIdBuffer = std.mem.zeroes([16]u8),
            .tuples = Tuples.init(alloc),
            .outputWriter = std.io.bufferedWriter(outputFile.writer()),
            .outputFile = outputFile,
        };

        try outputFile.writeAll(crt1);

        return rt;
    }

    pub fn setSourceName(self: *Self, to: t.String) !void {
        try std.fmt.format(self.outputWriter.writer(), "#define DOPPELGANGER_SOURCE_NAME \"{s}\"\n", .{to});

        log.info("set name to {s}", .{to});
    }

    inline fn showInstropectLog(item: anytype) void {
        log.debug("converting {s} at {s}:{}:{}", .{
            @typeName(@TypeOf(item)),
            item.location.filename,
            item.location.start,
            item.location.end,
        });
    }

    inline fn termToJitKind(term: spec.Term) jitKinds {
        return switch (term) {
            .int => .Int32,
            .boolean => .Boolean,
            .str => .Str,
            .function => .Function,
            else => unreachable,
        };
    }

    inline fn requestEvaluationId(self: *Self) EvaluationID {
        _ = std.fmt.bufPrint(&self.evalIdBuffer, "E_{:0>14}", .{self.currentEvalId}) catch unreachable;
        self.currentEvalId += 1;

        return self.evalIdBuffer;
    }

    fn buildTuple(self: *Self, first: EvaluationID, second: EvaluationID) !EvaluationID {
        const eId = self.requestEvaluationId();

        try std.fmt.format(
            self.outputWriter.writer(),
            \\static {s} {s} = {{
            \\.first = &{s},
            \\.second = &{s},
            \\}};
        ,
            .{
                jitKinds.Tuple.toString(),
                eId,
                first,
                second,
            },
        );

        // try self.tuples.put(TuplePrimitive{ .first = termToJitKind(first), .second = termToJitKind(second) }, self.requestEvaluationId());

        return self.requestEvaluationId();
    }

    fn insertEvaluation(self: *Self, term: spec.Term) !EvaluationID {
        const eId = self.requestEvaluationId();

        switch (term) {
            .str => |v| {
                showInstropectLog(v);
                try std.fmt.format(
                    self.outputWriter.writer(),
                    "static {s} {s} = \"{s}\";",
                    .{
                        jitKinds.Str.toString(),
                        eId,
                        v.value,
                    },
                );
            },

            .int => |i| {
                showInstropectLog(i);
                try std.fmt.format(
                    self.outputWriter.writer(),
                    "static {s} {s} = {};",
                    .{
                        jitKinds.Int32.toString(),
                        eId,
                        i.value,
                    },
                );
            },

            .tuple => |v| {
                showInstropectLog(v);
                const first = try self.insertEvaluation(v.first);
                const second = try self.insertEvaluation(v.second);
                log.debug("creating tuple ({s}, {s})", .{ first, second });
                return try self.buildTuple(first, second);
            },

            else => |v| {
                log.warn("unimplemented {any}", .{v});
            },
        }

        return eId;
    }

    pub fn pushRoot(self: *Self, term: spec.Term) !void {
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.debug("NuclearFlags: noop marked.", .{});
            return;
        }

        switch (term) {
            .let => |let| {
                showInstropectLog(let);
                const valueId = try self.insertEvaluation(let.value);
                _ = valueId;
                log.debug("Loading variable: {s}", .{let.name.text});
            },

            .boolean => |it| {
                _ = it;
            },

            else => |it| {
                log.err("unimplemented: {s}", .{@tagName(it)});
            },
        }
    }

    pub fn deinit(self: *Self) void {
        self.engine.deinit();
        self.tuples.deinit();
        _ = self.outputWriter.flush() catch 0;
        self.outputFile.close();
    }
};
