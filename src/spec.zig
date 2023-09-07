pub const TermKind = enum { Let, Function };
pub const KeyName = enum { kind, value, name, text, then, location, next, start, end, filename };
pub const Location = struct { start: Int, end: Int, filename: []const u8 };
pub const Parameter = struct { text: []const u8, location: Location };

pub const Int = i32;
