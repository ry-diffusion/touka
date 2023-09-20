const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const functionArgument = "WorkState* s";
const libTouka = @embedFile("./touka.h");

const DependencyId = t.Id;
const Arguments = std.ArrayList(DependencyId);
const AutoHashMap = std.AutoHashMap;
const StringHM = std.StringHashMap;
const Tuple = std.meta.Tuple;

pub const Evaluation = union(enum) {
    unknown,
    reference: struct { to: DependencyId },

    function: struct {
        name: DependencyId,
        arguments: Arguments,
        body: DependencyId,
    },

    print: DependencyId,

    dependsOnCall: struct {
        callee: DependencyId,
        arguments: Arguments,
    },

    binary: struct {
        op: DependencyId,
        left: DependencyId,
        right: DependencyId,
    },

    constant: union(enum) {
        num: t.Int,
        str: DependencyId,
    },

    const Self = @This();

    inline fn isPure(self: *const Self) bool {
        return switch (self.*) {
            .function, .constant => true,
            .print => false,
            .dependsOnCall, .binary => false,
            .reference => false,
            else => false,
        };
    }

    inline fn isFunction(self: *const Self) bool {
        return switch (self.*) {
            .function => true,
            else => false,
        };
    }

    inline fn isDeclaration(self: *const Self) bool {
        return switch (self.*) {
            .function, .constant => true,
            else => false,
        };
    }
};

const format = std.fmt.allocPrint;
pub const Phase = enum { parsing, generating };
pub const Error = error{ SemanticAnalysisFailed, OutOfMemory };

pub const Generator = struct {
    const EvaluationMap = std.AutoArrayHashMap(DependencyId, Evaluation);
    const StringMap = AutoHashMap(DependencyId, t.String);

    alloc: std.mem.Allocator,
    phase: Phase,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,
    evaluations: EvaluationMap,
    strings: StringMap,

    totalDependencies: t.Id,
    file: std.fs.File,
    output: std.io.BufferedWriter(4096, std.fs.File.Writer),

    const log = std.log.scoped(.doppelganger);
    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) !Generator {
        const outputFile = try std.fs.cwd().createFile("DopplegangerOutput.c", .{});

        var rt = Generator{
            .alloc = alloc,
            .strings = StringMap.init(alloc),
            .engine = try engine.State.init(),
            .nuclearFlags = t.NuclearFlags.empty(),
            .totalDependencies = 3,
            .output = std.io.bufferedWriter(outputFile.writer()),
            .file = outputFile,
            .evaluations = EvaluationMap.init(alloc),
            .phase = Phase.parsing,
        };

        try outputFile.writeAll(libTouka);

        return rt;
    }

    pub fn setSourceName(self: *Self, to: t.String) !void {
        try std.fmt.format(self.output.writer(), "#define DOPPELGANGER_SOURCE_NAME \"{s}\"\n", .{to});
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

    inline fn append(self: *Self, fmt: t.String, args: anytype) !void {
        try std.fmt.format(self.output.writer(), fmt, args);
        _ = try self.output.write("\n");
    }

    fn putString(self: *Self, to: t.String) !DependencyId {
        var iter = self.strings.iterator();

        while (iter.next()) |item| {
            const id = @as(DependencyId, item.key_ptr.*);
            const str = @as(t.String, item.value_ptr.*);

            if (std.mem.eql(u8, str, to)) {
                return id;
            }
        }

        const id = self.getDependencyId();
        try self.strings.put(id, to);

        return id;
    }

    fn generateDeclaration(self: *Self, id: DependencyId, eval: Evaluation) !void {
        switch (eval) {
            .constant => |constant| {
                switch (constant) {
                    .num => |num| try self.append("const Num e_{} = {};", .{ id, num }),
                    .str => |strId| {
                        const str = self.strings.get(strId) orelse unreachable;
                        try self.append("const Str e_{} = \"{s}\";", .{ id, str });
                    },
                }
            },
            else => std.debug.panic("invalid declaration", .{}),
        }
    }

    pub fn generateExpression(self: *Self, id: DependencyId, eval: Evaluation) !void {
        _ = id;
        switch (eval) {
            .binary => |b| {
                const opStr = self.strings.get(b.op) orelse unreachable;
                log.debug("running {s}", .{opStr});
                const lhs = self.evaluations.fetchOrderedRemove(b.left).?.value;
                const rhs = self.evaluations.fetchOrderedRemove(b.right).?.value;
                log.debug("lhs = {any}; rhs = {any};", .{ lhs, rhs });
            },

            .print => |print| {
                _ = print;
                log.debug("TODO Print", .{});
            },

            else => std.debug.panic("invalid expression {any}", .{eval}),
        }
    }

    pub fn generate(self: *Self) !void {
        var evalsIter = self.evaluations.iterator();

        while (evalsIter.next()) |item| {
            const id = @as(DependencyId, item.key_ptr.*);
            const eval = @as(Evaluation, item.value_ptr.*);

            if (eval.isPure() and eval.isDeclaration()) {
                try self.generateDeclaration(id, eval);
            }

            if (!eval.isPure() and !eval.isFunction()) {
                try self.generateExpression(id, eval);
            }
        }

        try self.append("int main(void) {{", .{});
        try self.append("langLoop = tk_initLoop();", .{});

        defer self.append("}}", .{}) catch unreachable;
        defer self.append("return tk_run(langLoop, 0);", .{}) catch unreachable;
    }

    fn getDependencyId(self: *Self) DependencyId {
        self.totalDependencies += 1;

        return self.totalDependencies;
    }

    fn expandTerm(self: *Self, term: spec.Term) Error!DependencyId {
        const id = self.getDependencyId();

        switch (term) {
            .int => |dasTerm| {
                try self.evaluations.put(id, .{ .constant = .{ .num = dasTerm.value } });
            },

            .str => |dasStr| {
                const stringId = try self.putString(try self.alloc.dupe(u8, dasStr.value));
                try self.evaluations.put(id, .{ .constant = .{ .str = stringId } });
            },

            .binary => |dasBinary| {
                return try self.expandBinary(dasBinary);
            },

            .call => |call| {
                var node = call.arguments.popFirst();
                var arguments = Arguments.init(self.alloc);

                const calleeId = try self.expandTerm(call.callee);

                while (node) |n| : (node = n.next) {
                    try arguments.append(try self.expandTerm(n.data));
                }

                try self.evaluations.put(id, .{
                    .dependsOnCall = .{
                        .callee = calleeId,
                        .arguments = arguments,
                    },
                });
            },

            .nil => {
                try self.evaluations.put(id, .unknown);
            },

            .let => {
                try self.insert(term);
            },

            .print => |p| {
                try self.evaluations.put(id, .{ .print = try self.expandTerm(p.value) });
            },

            .varTerm => |dasRef| {
                const refNameId = try self.putString(try self.alloc.dupe(u8, dasRef.text));
                try self.evaluations.put(id, .{ .reference = .{ .to = refNameId } });
            },

            else => {
                std.debug.panic(".expandTerm unimplemented: {any}", .{term});
            },
        }

        return id;
    }

    fn expandBinary(self: *Self, binary: *spec.Binary) !DependencyId {
        const compStr = try self.alloc.dupe(u8, binary.op.asText());
        const opId = try self.putString(compStr);

        log.debug(".expandBinary: strMap({s},{d})", .{ compStr, opId });
        const lhs = try self.expandTerm(binary.lhs);
        const rhs = try self.expandTerm(binary.rhs);
        const id = self.getDependencyId();

        try self.evaluations.put(id, .{ .binary = .{ .op = opId, .left = lhs, .right = rhs } });

        return id;
    }

    fn expandFunction(self: *Self, name: t.String, func: *spec.Function, next: ?*spec.Term) !void {
        _ = next;
        showInstropectLog(func);
        log.debug("parsing function #{s}", .{name});
        var arguments = Arguments.init(self.alloc);
        var bodyId: ?DependencyId = null;

        switch (func.value) {
            .ifTerm => |ifTerm| {
                const binaryId = switch (ifTerm.condition) {
                    .binary => |binary| try self.expandBinary(binary),
                    else => |i| {
                        log.err("expected binary operation, found {any}", .{i});
                        return Error.SemanticAnalysisFailed;
                    },
                };

                const then = try self.expandTerm(ifTerm.then);
                _ = then;
                const else_ = try self.expandTerm(ifTerm.otherwise);
                _ = else_;

                _ = binaryId;
                log.info("hella", .{});
            },
            else => log.err(".expandFunction unimplemented: {any}", .{func.value}),
        }

        try self.evaluations.put(self.getDependencyId(), .{
            .function = .{
                .name = try self.putString(name),
                .arguments = arguments,
                .body = bodyId.?,
            },
        });
    }

    pub fn insert(self: *Self, term: spec.Term) !void {
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.warn("NuclearFlags: noop marked.", .{});
            return;
        }

        switch (term) {
            .let => |let| {
                const varName = let.name.text;

                switch (let.value) {
                    .function => |f| {
                        try self.expandFunction(varName, f, null);
                    },
                    .binary => |b| {
                        _ = try self.expandBinary(b);
                    },
                    else => log.warn(".insertLetValue unimplemented: {any}", .{let.value}),
                }

                switch (let.next) {
                    .nil => {},

                    else => |n| {
                        _ = try self.expandTerm(n);
                    },
                }

                log.debug(".insert: defLet({s})", .{varName});
            },
            else => |ter| log.warn(".insert unimplemented: {any}", .{ter}),
        }
    }

    pub fn deinit(self: *Self) void {
        var stringsIter = self.strings.iterator();

        while (stringsIter.next()) |item| {
            self.alloc.free(item.value_ptr.*);
        }

        self.engine.deinit();
        self.evaluations.deinit();
        self.strings.deinit();

        _ = self.output.flush() catch 0;
        self.file.close();
    }
};
