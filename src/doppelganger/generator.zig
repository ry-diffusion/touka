const std = @import("std");
const uv = @import("uv.zig");
const t = @import("types.zig");
const engine = @import("engine.zig");
const spec = @import("../spec.zig");
const functionArgument = "WorkState* s";
const libTouka = @embedFile("./touka.h");

const crash = std.debug.panic;
const DependencyId = t.Id;
const Arguments = std.ArrayList(DependencyId);
const AutoHashMap = std.AutoHashMap;
const StringHM = std.StringHashMap;
const Tuple = std.meta.Tuple;

const EvaluationBinary = struct {
    op: DependencyId,
    left: DependencyId,
    right: DependencyId,
};

const EvaluationBinaryProcessResult = struct { id: DependencyId, isPure: bool };
const EvaluationConstant = union(enum) {
    num: t.Int,
    str: DependencyId,
};

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

    binary: EvaluationBinary,

    constant: EvaluationConstant,
    const Self = @This();

    inline fn isPure(self: *const Self) bool {
        return switch (self.*) {
            .constant => true,
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

const RuntimeCall = union(enum) {
    print: union(enum) {
        str: DependencyId,
        num: t.Int,
        varTerm: DependencyId,
        staticText: []const u8,
    },
};

const UNKNOWN = "<#unknown>";
const CLOSURE = "<#closure>";

const format = std.fmt.allocPrint;
pub const Phase = enum { parsing, generating };
pub const Error = error{ SemanticAnalysisFailed, OutOfMemory };

pub const Generator = struct {
    const EvaluationMap = std.AutoHashMap(DependencyId, Evaluation);
    const StringMap = AutoHashMap(DependencyId, t.String);
    const RuntimeCallsQueue = std.ArrayList(RuntimeCall);

    alloc: std.mem.Allocator,
    phase: Phase,
    engine: engine.State,
    nuclearFlags: t.NuclearFlags,
    evaluations: EvaluationMap,
    strings: StringMap,
    runtimeCalls: RuntimeCallsQueue,

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
            .runtimeCalls = RuntimeCallsQueue.init(alloc),
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

    fn generateClassicDeclaration(self: *Self, id: DependencyId, eval: Evaluation) !void {
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

    fn binaryProccess(self: *Self, eval: Evaluation) !EvaluationBinaryProcessResult {
        const resultId = self.getDependencyId();
        var refId: ?DependencyId = null;
        var isPure: bool = false;
        try self.append("const Lazy e_{} = Unknown;", .{resultId});

        switch (eval) {
            .constant => |constant| switch (constant) {
                .num => |n| {
                    const numId = self.getDependencyId();
                    try self.append("const Num e_{} = {};", .{ numId, n });

                    isPure = true;

                    refId = numId;
                },

                .str => |strId| {
                    const str = self.strings.get(strId) orelse unreachable;
                    const strCodeId = self.getDependencyId();

                    refId = strCodeId;
                    try self.append("const Str e_{} = \"{s}\";", .{ strCodeId, str });
                },
            },

            .reference => |ref| {
                refId = ref.to;
            },

            else => std.debug.panic("invalid binary hand {any}", .{eval}),
        }

        try self.append("e_{} = &e_{};", .{ resultId, refId.? });

        return .{
            .id = resultId,
            .isPure = isPure,
        };
    }

    fn binaryL2LProcess(self: *Self, a: EvaluationConstant, b: EvaluationConstant) !DependencyId {
        const resultId = self.getDependencyId();
        var baseInt: ?t.Int = null;
        var baseStr: ?t.String = null;

        switch (a) {
            .num => |num| {
                baseInt = num;
            },

            .str => |strId| {
                baseStr = self.strings.get(strId) orelse unreachable;
            },
        }

        switch (b) {
            .num => |num| {
                if (baseInt) |bint|
                    try self.append("const Num e_{} = {} + {};", .{ resultId, bint, num });

                if (baseStr) |bstr|
                    try self.append("const Str e_{} = \"{s}\" \"{}\";", .{ resultId, bstr, num });
            },

            .str => |strId| {
                const str = self.strings.get(strId) orelse unreachable;

                if (baseStr) |bstr|
                    try self.append("const Str e_{} = \"{s}\" \"{s}\";", .{ resultId, bstr, str });

                if (baseInt) |bint|
                    try self.append("const Str e_{} = \"{}\" \"{s}\";", .{ resultId, bint, str });
            },
        }

        return resultId;
    }

    fn fetchEvaluation(self: *Self, id: DependencyId) ?Evaluation {
        if (self.evaluations.fetchRemove(id)) |k| {
            return k.value;
        }

        return null;
    }

    fn generateBinary(self: *Self, id: DependencyId, b: EvaluationBinary) !void {
        _ = id;

        const opStr = self.strings.get(b.op) orelse unreachable;
        log.debug("running {s}", .{opStr});
        const lhs = self.fetchEvaluation(b.left).?;
        const rhs = self.fetchEvaluation(b.right).?;

        if (lhs.isPure() and rhs.isPure()) {
            _ = try self.binaryL2LProcess(lhs.constant, rhs.constant);
        }

        log.debug(".generateBinary: {any} {s} {any};", .{ lhs, opStr, rhs });
    }

    fn expandPrint(self: *Self, id: DependencyId) !DependencyId {
        const value = self.fetchEvaluation(id).?;

        switch (value) {
            .constant => |constant| switch (constant) {
                .str => |strId| {
                    try self.runtimeCalls.append(.{
                        .print = .{
                            .str = strId,
                        },
                    });
                },

                .num => |n| {
                    try self.runtimeCalls.append(.{
                        .print = .{
                            .num = n,
                        },
                    });
                },
            },

            .reference => |ref| {
                return try self.expandPrint(ref.to);
            },

            .function => |f| {
                _ = f;
                try self.runtimeCalls.append(.{
                    .print = .{
                        .staticText = CLOSURE,
                    },
                });
            },

            .print => |p| {
                return try self.expandPrint(p);
            },

            .binary => |b| {
                crash(".expandPrint: unimplemented {any}", .{b});
                // const res = try self.expandBinary(b);
                // return try self.expandPrint(res);
            },

            .dependsOnCall => |d| {
                crash(".expandPrint: unimplemented {any}", .{d});
            },

            .unknown => {
                try self.runtimeCalls.append(.{
                    .print = .{
                        .staticText = UNKNOWN,
                    },
                });
            },
        }

        return id;
    }

    fn generateExpression(self: *Self, id: DependencyId, eval: Evaluation) !void {
        switch (eval) {
            .binary => |b| try self.generateBinary(id, b),
            .print => |valueId| {
                _ = try self.expandPrint(valueId);
            },

            .function => |f| {
                log.warn("TODO Function #{s}", .{self.strings.get(f.name) orelse "???"});
            },

            else => std.debug.panic(".generateExpression: invalid expression {any}", .{eval}),
        }
    }

    pub fn generate(self: *Self) !void {
        var evalsIter = self.evaluations.iterator();

        while (evalsIter.next()) |item| {
            const id = @as(DependencyId, item.key_ptr.*);
            const eval = @as(Evaluation, item.value_ptr.*);

            if (eval == .unknown) {
                @panic("found unknown, UB detected.");
            }

            log.debug(".generate: is function? {} is pure? {} is declaration? {}", .{
                eval.isFunction(),
                eval.isPure(),
                eval.isDeclaration(),
            });

            if (eval.isPure() and eval.isDeclaration()) {
                try self.generateClassicDeclaration(id, eval);
            }

            if (!eval.isPure() and !eval.isFunction()) {
                try self.generateExpression(id, eval);
            }
        }

        try self.append("int main(void) {{", .{});
        try self.append("langLoop = tk_initLoop();", .{});
        self.append("tk_run(langLoop, 0);", .{}) catch unreachable;

        log.info("RuntimeCalls len: {}", .{self.runtimeCalls.items.len});

        for (self.runtimeCalls.items) |item| {
            switch (item) {
                .print => |p| {
                    switch (p) {
                        .str => |strId| {
                            const str = self.strings.get(strId) orelse unreachable;
                            try self.append("tk_printStrNat(\"{s}\");", .{str});
                        },

                        .staticText => |text| {
                            try self.append("tk_printStrNat(\"{s}\");", .{text});
                        },

                        .num => |num| {
                            try self.append("tk_printNumNat({});", .{num});
                        },

                        .varTerm => |v| {
                            _ = v;
                            @panic("unimplemented VarTerm in Generate.");
                        },
                    }
                },
            }
        }

        defer self.append("}}", .{}) catch unreachable;
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
                log.debug(".expandTerm: print {any}", .{p.value});
                try self.evaluations.put(id, .{ .print = try self.expandTerm(p.value) });
            },

            .varTerm => |dasRef| {
                const refNameId = try self.putString(try self.alloc.dupe(u8, dasRef.text));
                try self.evaluations.put(id, .{ .reference = .{ .to = refNameId } });
            },

            else => crash(".expandTerm unimplemented: {any}", .{term}),
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

    fn expandFunction(self: *Self, name: t.String, func: *spec.Function, next: ?*spec.Term) !DependencyId {
        _ = next;
        showInstropectLog(func);
        const id = self.getDependencyId();
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

        return id;
    }

    fn evaluateTerm(self: *Self, term: spec.Term, varName: ?t.String) !DependencyId {
        const id = self.getDependencyId();
        return switch (term) {
            .function => |f| try self.expandFunction(varName.?, f, null),
            .str => |c| {
                const strId = try self.putString(try self.alloc.dupe(u8, c.value));
                try self.evaluations.put(id, .{ .constant = .{ .str = strId } });

                return id;
            },
            .int => |i| {
                try self.evaluations.put(id, .{ .constant = .{ .num = i.value } });

                return id;
            },
            .binary => |b| try self.expandBinary(b),

            else => crash(".putValue unimplemented: {any}", .{term}),
        };
    }

    pub fn insert(self: *Self, term: spec.Term) !void {
        if (self.nuclearFlags.forceNoop == t.NuclearFlags.enabled) {
            log.warn("NuclearFlags: noop marked.", .{});
            return;
        }

        switch (term) {
            .let => |let| {
                const varName = let.name.text;

                _ = try self.evaluateTerm(let.value, varName);

                switch (let.next) {
                    .nil => {},

                    else => |n| {
                        _ = try self.expandTerm(n);
                    },
                }

                log.debug(".insert: defLet({s})", .{varName});
            },

            .print => |p| {
                log.info("printValue: {any}", .{p.value});

                const itemId = try self.evaluateTerm(p.value, null);
                try self.evaluations.put(self.getDependencyId(), .{ .print = itemId });
            },

            else => |ter| crash(".insert unimplemented: {any}", .{ter}),
        }
    }

    pub fn deinit(self: *Self) void {
        var stringsIter = self.strings.iterator();

        while (stringsIter.next()) |item| {
            self.alloc.free(item.value_ptr.*);
        }

        _ = self.output.flush() catch 0;
        self.file.close();

        self.evaluations.deinit();
        self.runtimeCalls.deinit();

        self.strings.deinit();
        self.engine.deinit();
    }
};
