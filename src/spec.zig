const std = @import("std");
pub const TermKind = enum { Let, Function };
pub const KeyName = enum {
    kind,
    value,
    name,
    text,
    then,
    location,
    next,
    start,
    end,
    parameters,
    filename,
};

pub const Location = struct {
    start: Int,
    end: Int,
    filename: []const u8,

    pub fn empty() Location {
        return Location{
            .start = 0,
            .end = 0,
            .filename = "",
        };
    }
};
pub const Parameter = struct { text: []const u8, location: Location };
pub const Function = struct {
    parameters: Parameters,
    value: Term,
    location: Location,

    pub const Parameters = std.SinglyLinkedList(Parameter);

    pub fn empty() Function {
        return Function{
            .parameters = std.SinglyLinkedList(Parameter){},
            .value = Term.nil(),
            .location = Location.empty(),
        };
    }
};
pub const Let = struct { name: Parameter, value: Term, next: Term, location: Location };

pub const Term = union(enum) {
    function: *Function,
    let: *Let,
    nil: ?void,

    pub fn nil() Term {
        return Term{ .nil = null };
    }
};

pub const Int = i32;
