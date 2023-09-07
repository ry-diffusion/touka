const std = @import("std");
const mem = std.mem;
const AllocWhen = std.json.AllocWhen;
const rt = @import("doppelganger/runtime.zig");

const ReaderStage = enum { readingRoot, readingAst };

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

    pub fn next(self: *AstReader) !bool {
        const token = try self.source.next();
        switch (token) {
            .object_begin => {
                log.debug("reading object", .{});
            },

            .string => |str| {
                switch (self.stage) {
                    .readingRoot => {
                        if (mem.eql(u8, str, "name")) {
                            const vmName = switch (self.source.next() catch {
                                log.warn("Root:name is empty. But it is required, so I now calling my mom to report u", .{});
                                return false;
                            }) {
                                .allocated_string, .string => |s| s,
                                else => {
                                    log.err("Root:name must be a str", .{});
                                    return false;
                                },
                            };

                            try self.runtime.setSourceName(vmName);
                            return true;
                        }

                        if (mem.eql(u8, str, "expression")) {
                            self.stage = .readingAst;
                        }
                    },

                    .readingAst => {},
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
