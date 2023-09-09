const std = @import("std");
const spec = @import("spec.zig");
const rt = @import("doppelganger/runtime.zig");
const box = @import("mem.zig").box;
const mem = std.mem;
const AllocWhen = std.json.AllocWhen;
const ReaderStage = enum { readingRoot, readingInitialAst, readingAst };

pub const ParseError = error{
    TypeMismatch,
    NoValueFound,
    InvalidKey,
    InvalidTerm,
    Unimplemented,
};

pub const Error = (ParseError || std.json.Scanner.NextError);

pub const AstReader = struct {
    runtime: *rt.Runtime,
    stage: ReaderStage,
    alloc: mem.Allocator,
    howDeep: u64,
    source: std.json.Reader(std.json.default_buffer_size, std.fs.File.Reader),

    const log = std.log.scoped(.astReader);

    pub fn fromFile(alloc: std.mem.Allocator, runtime: *rt.Runtime, reader: std.fs.File.Reader) AstReader {
        const source = std.json.reader(alloc, reader);

        return AstReader{
            .alloc = alloc,
            .source = source,
            .howDeep = 0,
            .runtime = runtime,
            .stage = ReaderStage.readingRoot,
        };
    }

    pub fn deinit(self: *AstReader) void {
        self.source.deinit();
    }

    fn traverse(self: *@This()) Error!void {
        while ((self.source.peekNextTokenType() catch {
            return Error.SyntaxError;
        }) == std.json.TokenType.object_end) {
            self.howDeep += 1;
            log.debug("depth: {}", .{self.howDeep});

            _ = self.source.next() catch {
                return Error.SyntaxError;
            };

            break;
        }
    }

    fn expectString(self: *@This(), why: []const u8) Error![]const u8 {
        const item = self.source.nextAlloc(self.alloc, std.json.AllocWhen.alloc_if_needed) catch {
            log.err("expected a string: {s}", .{why});
            return Error.NoValueFound;
        };

        switch (item) {
            .allocated_string => |s| return s,
            .string => |s| return s,

            else => |i| {
                log.err("expected a string, found {any}", .{i});
                return Error.TypeMismatch;
            },
        }
    }

    fn expectBool(self: *@This(), why: []const u8) Error!bool {
        const item = self.source.next() catch {
            log.err("expected a boolean: {s}", .{why});
            return Error.NoValueFound;
        };

        switch (item) {
            .true => return true,
            .false => return false,

            else => |i| {
                log.err("expected a boolean, found {any}", .{i});
                return Error.TypeMismatch;
            },
        }
    }

    fn readRootStringManifest(self: *@This(), str: []const u8) Error!void {
        if (mem.eql(u8, str, "name")) {
            const vmName = try self.expectString("root:name must be not empty.");
            try self.runtime.setSourceName(vmName);
        } else if (mem.eql(u8, str, "expression")) {
            self.stage = .readingInitialAst;
        }
    }

    fn instropectEntry(self: *@This(), str: []const u8) Error!void {
        log.debug("ast.root: {s}", .{str});

        const key = strAsKey(str) orelse {
            log.err("entryReader: unexpected key: {s}", .{str});
            return Error.InvalidKey;
        };

        switch (key) {
            .kind => {
                const term = try self.instropectTerm();

                switch (term) {
                    .let => |let| {
                        log.debug("definindo {any}", .{let});
                        self.alloc.destroy(let);
                    },

                    .boolean => |boo| {
                        log.debug("booleano {any}", .{boo});
                    },

                    .tuple => |t| {
                        log.debug("bota um halls na lingua amor: ({any}, {any})", .{ t.first, t.second });
                        self.alloc.destroy(t);
                    },

                    .str => |opa| {
                        log.debug("string {s}", .{opa.value});
                        // self.alloc.destroy(opa.value.ptr);
                    },

                    .print => |p| {
                        log.debug("pq n né? vo mostrar assim kk {any}", .{p});
                        self.alloc.destroy(p);
                    },

                    .call => |discord| {
                        log.debug("eodiscord {any}", .{discord});
                        self.alloc.destroy(discord);
                    },

                    .int => |int| {
                        log.debug("inteiro: {}", .{int.value});
                    },

                    .varTerm => |let| {
                        log.debug("usando {any}", .{let});
                        self.alloc.destroy(let);
                    },

                    .binary => |let| {
                        log.debug("0101 {any}", .{let});
                        self.alloc.destroy(let);
                    },

                    .ifTerm => |let| {
                        log.debug("se {any}", .{let});
                        self.alloc.destroy(let);
                    },

                    .function => |func| {
                        log.debug("functs: {any}", .{func});
                        self.alloc.destroy(func);
                    },

                    .nil => {},
                }
            },

            .location => {
                _ = try self.instropectLocation();
            },

            else => |s| {
                std.debug.panic("unimplemented: {any}", .{s});
            },
        }
    }

    fn instropectLocation(self: *@This()) Error!spec.Location {
        try self.expectTreeStart();
        var loc = spec.Location.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            switch (key) {
                .start => loc.start = try self.expectInt("expected location.start as a integer."),
                .end => loc.end = try self.expectInt("expected location.end as a integer"),
                .filename => loc.filename = try self.expectString("expected location.filename as a string"),
                else => return Error.InvalidKey,
            }
        }

        try self.expectTreeEnd();
        return loc;
    }

    fn instropectParameter(self: *@This()) Error!spec.Parameter {
        try self.expectTreeStart();

        var param = spec.Parameter{ .location = spec.Location.empty(), .text = "" };

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            switch (key) {
                .text => param.text = try self.expectString("expected param.text found nothing"),
                .location => param.location = try self.instropectLocation(),
                else => return Error.InvalidKey,
            }
        }

        try self.traverse();

        return param;
    }

    fn instropectTerm(self: *@This()) Error!spec.Term {
        if (self.stage == .readingInitialAst) {
            self.stage = .readingAst;
        } else {
            try self.expectTreeStart();
            if (try self.expectKey() != .kind) {
                return Error.InvalidKey;
            }
        }

        const kind = try self.expectTerm();
        var term = spec.Term.nil();

        switch (kind) {
            .Bool => term = spec.Term{ .boolean = try self.instropectBoolean() },
            .Str => term = spec.Term{ .str = try self.instropectStr() },
            .Int => term = spec.Term{ .int = try self.instropectInt() },
            .Tuple => term = spec.Term{ .tuple = try box(self.alloc, spec.Tuple, try self.instropectTuple()) },
            .Print => term = spec.Term{ .print = try box(self.alloc, spec.Print, try self.instropectPrint()) },
            .Var => term = spec.Term{ .varTerm = try box(self.alloc, spec.Var, try self.instropectVar()) },
            .Call => term = spec.Term{ .call = try box(self.alloc, spec.Call, try self.instropectCall()) },
            .Binary => term = spec.Term{ .binary = try box(self.alloc, spec.Binary, try self.instropectBinary()) },
            .Let => term = spec.Term{ .let = try box(self.alloc, spec.Let, try self.instropectLet()) },
            .If => term = spec.Term{ .ifTerm = try box(self.alloc, spec.If, try self.instropectIf()) },
            .Function => term = spec.Term{ .function = try box(self.alloc, spec.Function, try self.instropectFunction()) },
        }

        try self.traverse();
        return term;
    }

    fn instropectBoolean(self: *@This()) Error!spec.Bool {
        var term = spec.Bool.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            switch (key) {
                .value => term.value = try self.expectBool("I need a str tho"),
                .location => term.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return term;
    }

    fn instropectStr(self: *@This()) Error!spec.Str {
        var term = spec.Str.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            switch (key) {
                .value => term.value = try self.expectString("I need a str tho"),
                .location => term.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return term;
    }

    fn instropectInt(self: *@This()) Error!spec.IntTerm {
        var term = spec.IntTerm.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            switch (key) {
                .value => term.value = try self.expectInt("I need a int tho"),
                .location => term.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return term;
    }

    fn instropectTuple(self: *@This()) Error!spec.Tuple {
        var term = spec.Tuple.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            switch (key) {
                .first => term.first = try self.instropectTerm(),
                .second => term.second = try self.instropectTerm(),
                .location => term.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return term;
    }

    fn instropectPrint(self: *@This()) Error!spec.Print {
        var term = spec.Print.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            switch (key) {
                .value => term.value = try self.instropectTerm(),

                .location => term.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return term;
    }
    fn instropectVar(self: *@This()) Error!spec.Var {
        var term = spec.Var.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            switch (key) {
                .text => term.text = try self.expectString("expecting a referal variable name"),
                .location => term.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return term;
    }

    fn instropectBinary(self: *@This()) Error!spec.Binary {
        var binary = spec.Binary.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            log.debug("binary: {any}", .{key});

            switch (key) {
                .op => {
                    binary.op = try self.instropectBinaryOperation();
                    continue;
                },
                .rhs => binary.rhs = try self.instropectTerm(),
                .lhs => binary.lhs = try self.instropectTerm(),
                .location => binary.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return binary;
    }

    fn instropectBinaryOperation(self: *@This()) Error!spec.BinaryOp {
        const rawBinaryOp = try self.expectString("expected a op:string found nothing instead.");
        return std.meta.stringToEnum(spec.BinaryOp, rawBinaryOp) orelse Error.NoValueFound;
    }

    fn instropectIf(self: *@This()) Error!spec.If {
        var dasIf = spec.If.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            log.debug("if: {any}", .{key});

            switch (key) {
                .condition => dasIf.condition = try self.instropectTerm(),
                .then => dasIf.then = try self.instropectTerm(),
                .otherwise => dasIf.then = try self.instropectTerm(),
                .location => dasIf.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        return dasIf;
    }

    fn instropectCall(self: *@This()) Error!spec.Call {
        var call = spec.Call.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            switch (key) {
                .arguments => try self.parseCallArguments(&call.arguments),
                .callee => call.callee = try self.instropectTerm(),
                .location => call.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        try self.traverse();

        return call;
    }

    fn instropectFunction(self: *@This()) Error!spec.Function {
        //try self.expectTreeStart();
        var func = spec.Function.empty();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            switch (key) {
                .parameters => try self.parseParameters(&func.parameters),
                .value => func.value = try self.instropectTerm(),
                .location => func.location = try self.instropectLocation(),
                else => return Error.Unimplemented,
            }
        }

        try self.traverse();

        return func;
    }

    fn parseParameters(self: *@This(), params: *spec.Function.Parameters) Error!void {
        try self.expect(.array_begin);

        while (!try self.isArrayFinished()) {
            const res = try self.instropectParameter();
            var node = spec.Function.Parameters.Node{ .data = res };
            params.prepend(&node);
        }

        try self.expect(.array_end);
    }

    fn parseCallArguments(self: *@This(), params: *spec.Call.Arguments) Error!void {
        try self.expect(.array_begin);

        while (!try self.isArrayFinished()) {
            const res = try self.instropectTerm();
            var node = spec.Call.Arguments.Node{ .data = res };
            params.prepend(&node);
        }

        try self.expect(.array_end);
    }

    fn instropectLet(self: *@This()) Error!spec.Let {
        var let = spec.Let{
            .location = spec.Location.empty(),
            .name = spec.Parameter{ .location = spec.Location.empty(), .text = "" },
            .next = spec.Term.nil(),
            .value = spec.Term.nil(),
        };

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            log.debug("let: {any}", .{key});

            switch (key) {
                .name => let.name = try self.instropectParameter(),
                .value => let.value = try self.instropectTerm(),
                .next => let.next = try self.instropectTerm(),
                .location => let.location = try self.instropectLocation(),
                else => return Error.InvalidKey,
            }
        }

        return let;
    }

    fn strAsTerm(str: []const u8) ?spec.TermKind {
        return std.meta.stringToEnum(spec.TermKind, str);
    }

    fn strAsKey(str: []const u8) ?spec.KeyName {
        return std.meta.stringToEnum(spec.KeyName, str);
    }

    fn expect(self: *@This(), want: std.json.TokenType) Error!void {
        const found = self.source.next() catch {
            log.err("Expected a {any} found nothing instead", .{want});
            return Error.NoValueFound;
        };

        if (@intFromEnum(found) != @intFromEnum(want)) {
            log.err("Expected a {any} found {any} instead", .{ want, found });
            return Error.TypeMismatch;
        }
    }

    fn expectTreeEnd(self: *@This()) Error!void {
        const token = self.source.next() catch {
            log.err("Expected a }}  found nothing instead", .{});
            return Error.NoValueFound;
        };

        switch (token) {
            .object_end => {},
            else => |e| {
                log.err("Expected a }} found {any} instead", .{e});
                return Error.TypeMismatch;
            },
        }
    }

    fn expectTreeStart(self: *@This()) Error!void {
        const token = self.source.next() catch {
            log.err("Expected a {{ found nothing instead", .{});
            return Error.NoValueFound;
        };

        switch (token) {
            .object_begin => {},
            else => |e| {
                log.err("Expected a {{ found {any} instead", .{e});
                return Error.TypeMismatch;
            },
        }
    }

    fn expectKey(self: *@This()) Error!spec.KeyName {
        const strKey = try self.expectString("expected a key.");

        return strAsKey(strKey) orelse {
            log.err("keyReader: unexpected key: {s}", .{strKey});
            return Error.InvalidKey;
        };
    }

    fn expectInt(self: *@This(), why: []const u8) Error!spec.Int {
        const item = self.source.next() catch {
            log.err("expected a int: {s}", .{why});
            return Error.NoValueFound;
        };

        switch (item) {
            .allocated_number, .number, .partial_number => |bytes| return std.fmt.parseInt(spec.Int, bytes, 10) catch 0,

            else => |i| {
                log.err("expected a number, found {any}", .{i});
                return Error.TypeMismatch;
            },
        }
    }

    fn expectTerm(self: *@This()) Error!spec.TermKind {
        const strTerm = try self.expectString("expected a kind:term.");

        return strAsTerm(strTerm) orelse {
            log.err("unexpected term: {s}", .{strTerm});
            return Error.InvalidTerm;
        };
    }

    fn isTreeFinished(self: *@This()) Error!bool {
        switch (self.source.peekNextTokenType() catch |e| {
            log.err("parse error: {any}", .{e});
            return Error.SyntaxError;
        }) {
            .object_begin, .object_end, .end_of_document => return true,
            else => return false,
        }
    }

    fn isArrayFinished(self: *@This()) Error!bool {
        switch (self.source.peekNextTokenType() catch |e| {
            log.err("parse error: {any}", .{e});
            return Error.SyntaxError;
        }) {
            .array_begin, .array_end, .end_of_document => return true,
            else => return false,
        }
    }

    pub fn next(self: *AstReader) !bool {
        const token = try self.source.next();
        switch (token) {
            .object_begin => {
                log.debug("reading object", .{});
            },

            .string => |str| {
                switch (self.stage) {
                    .readingRoot => try self.readRootStringManifest(str),
                    .readingInitialAst, .readingAst => try self.instropectEntry(str),
                }
            },

            .object_end, .end_of_document => return false,
            .null => return true,
            else => |i| {
                log.debug("ignoring {any}", .{i});
                return false;
            },
        }

        return true;
    }

    pub fn parseEntire(parentAllocator: mem.Allocator, runtime: *rt.Runtime, reader: std.fs.File.Reader) !AstReader {
        var arena = std.heap.ArenaAllocator.init(parentAllocator);
        var alloc = arena.allocator();
        defer arena.deinit();

        var astReader = AstReader.fromFile(alloc, runtime, reader);
        defer astReader.deinit();

        var timer = try std.time.Timer.start();
        while (try astReader.next()) {}

        const elapsed = timer.read();
        log.debug("read ast took: {}ms ({}us)", .{ elapsed / 1000 / 1000, elapsed / 1000 });

        return astReader;
    }
};
