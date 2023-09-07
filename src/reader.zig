const std = @import("std");
const spec = @import("spec.zig");
const rt = @import("doppelganger/runtime.zig");
const mem = std.mem;
const AllocWhen = std.json.AllocWhen;
const ReaderStage = enum { readingRoot, readingAst };
pub const Error = error{
    TypeMismatch,
    NoValueFound,
    InvalidKey,
    InvalidTerm,
    Unimplemented,
};

pub const AstReader = struct {
    runtime: *rt.Runtime,
    stage: ReaderStage,
    alloc: mem.Allocator,
    source: std.json.Reader(std.json.default_buffer_size, std.fs.File.Reader),
    const log = std.log.scoped(.astReader);

    pub fn fromFile(alloc: std.mem.Allocator, runtime: *rt.Runtime, reader: std.fs.File.Reader) AstReader {
        const source = std.json.reader(alloc, reader);

        return AstReader{
            .alloc = alloc,
            .source = source,

            .runtime = runtime,
            .stage = ReaderStage.readingRoot,
        };
    }

    pub fn deinit(self: *AstReader) void {
        self.source.deinit();
    }

    fn expectString(self: *@This(), why: []const u8) Error![]const u8 {
        const item = self.source.next() catch {
            log.err("expected a string: {s}", .{why});
            return Error.NoValueFound;
        };

        switch (item) {
            .allocated_string, .string => |s| return s,

            else => |i| {
                log.err("expected a string, found {any}", .{i});
                return Error.TypeMismatch;
            },
        }
    }

    fn readRootStringManifest(self: *@This(), str: []const u8) !void {
        if (mem.eql(u8, str, "name")) {
            const vmName = try self.expectString("root:name must be not empty.");
            try self.runtime.setSourceName(vmName);
        } else if (mem.eql(u8, str, "expression")) {
            self.stage = .readingAst;
        }
    }

    fn instropectEntry(self: *@This(), str: []const u8) !void {
        log.debug("ast.root: {s}", .{str});

        const key = strAsKey(str) orelse {
            log.err("unexpected key: {s}", .{str});
            return Error.InvalidKey;
        };

        switch (key) {
            .kind => {
                const term = try self.expectTerm();
                log.debug("found term: {any}", .{term});

                switch (term) {
                    .Let => return try self.instropectLet(),
                    .Function => return Error.Unimplemented,
                }
            },

            else => return Error.Unimplemented,
        }
    }

    fn instropectLocation(self: *@This()) !spec.Location {
        try self.expectTreeStart();
        var loc = spec.Location{ .start = 0, .end = 0, .filename = "" };

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            switch (key) {
                .start => {
                    loc.start = try self.expectInt("expected location.start as a integer.");
                },
                .end => {
                    loc.end = try self.expectInt("expected location.end as a integer");
                },
                .filename => {
                    loc.filename = try self.expectString("expected location.filename as a string");
                },
                else => return Error.InvalidKey,
            }
        }

        return loc;
    }

    fn instropectParameter(self: *@This()) !spec.Parameter {
        var param = spec.Parameter{ .location = spec.Location{ .start = 0, .end = 0, .filename = "" }, .text = "" };
        try self.expectTreeStart();

        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();

            switch (key) {
                .text => param.text = try self.expectString("expected param.text found nothing"),
                .location => param.location = try self.instropectLocation(),
                else => return Error.InvalidKey,
            }
        }

        return param;
    }

    fn instropectLet(self: *@This()) !void {
        while (!try self.isTreeFinished()) {
            const key = try self.expectKey();
            log.debug("--> {any}", .{key});

            switch (key) {
                .name => {
                    const param = try self.instropectParameter();
                    log.debug("{any}", .{param});
                },
                .value => {},
                .next => {},
                .location => {
                    _ = try self.instropectLocation();
                },
                else => return Error.InvalidKey,
            }
        }
    }

    fn strAsTerm(str: []const u8) ?spec.TermKind {
        return std.meta.stringToEnum(spec.TermKind, str);
    }

    fn strAsKey(str: []const u8) ?spec.KeyName {
        return std.meta.stringToEnum(spec.KeyName, str);
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
            log.err("unexpected key: {s}", .{strKey});
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

    fn isTreeFinished(self: *@This()) !bool {
        switch (try self.source.peekNextTokenType()) {
            .object_begin, .object_end, .end_of_document => return true,
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
                    .readingAst => try self.instropectEntry(str),
                }
            },

            .end_of_document => return false,
            .null => return true,
            else => {
                return false;
            },
        }

        return true;
    }
};
