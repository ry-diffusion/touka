const std = @import("std");
pub const TermKind = enum {
    Let,
    Function,
    If,
    Binary,
    Var,
    Int,
    Call,
    Print,
    Str,
    Tuple,
    Bool,
};

pub const BinaryOp = enum {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Eq,
    Neq,
    Lt,
    Gt,
    Lte,
    Gte,
    And,
    Or,

    pub fn asText(self: BinaryOp) []const u8 {
        return switch (self) {
            .Add => "+",
            .Sub => "-",
            .Mul => "*",
            .Div => "/",
            .Rem => "%",
            .Eq => "==",
            .Neq => "!=",
            .Lt => "<",
            .Gt => ">",
            .Lte => "<=",
            .Gte => ">=",
            .And => "&&",
            .Or => "||",
        };
    }
};
pub const KeyName = enum { kind, value, name, text, then, location, condition, otherwise, next, start, end, lhs, rhs, op, callee, arguments, parameters, filename, first, second };

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
pub const Call = struct {
    callee: Term,

    arguments: Arguments,
    location: Location,

    pub const Arguments = std.SinglyLinkedList(Term);

    pub fn empty() Call {
        return Call{
            .arguments = Arguments{},
            .callee = Term.nil(),
            .location = Location.empty(),
        };
    }
};

pub const Print = struct {
    location: Location,
    value: Term,

    pub fn empty() Print {
        return Print{ .location = Location.empty(), .value = Term.nil() };
    }
};

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
pub const IntTerm = struct {
    value: i32,
    location: Location,

    pub fn empty() IntTerm {
        return IntTerm{ .value = -1, .location = Location.empty() };
    }
};

pub const If = struct {
    condition: Term,
    then: Term,
    otherwise: Term,
    location: Location,

    pub fn empty() If {
        return If{
            .condition = Term.nil(),
            .then = Term.nil(),
            .otherwise = Term.nil(),
            .location = Location.empty(),
        };
    }
};

pub const Str = struct {
    value: []const u8,
    location: Location,

    pub fn empty() Str {
        return Str{ .value = "", .location = Location.empty() };
    }
};

pub const Bool = struct {
    value: bool,
    location: Location,

    pub fn empty() Bool {
        return Bool{
            .value = false,
            .location = Location.empty(),
        };
    }
};

pub const Tuple = struct {
    first: Term,
    second: Term,
    location: Location,

    pub fn empty() Tuple {
        return Tuple{
            .first = Term.nil(),
            .second = Term.nil(),
            .location = Location.empty(),
        };
    }
};

pub const Var = struct {
    text: []const u8,
    location: Location,

    pub fn empty() Var {
        return Var{ .text = "", .location = Location.empty() };
    }
};

pub const Binary = struct {
    op: BinaryOp,
    lhs: Term,
    rhs: Term,
    location: Location,

    pub fn empty() Binary {
        return Binary{
            .op = BinaryOp.Eq,
            .lhs = Term.nil(),
            .rhs = Term.nil(),
            .location = Location.empty(),
        };
    }
};

pub const Term = union(enum) {
    function: *Function,
    let: *Let,
    ifTerm: *If,
    varTerm: *Var,
    binary: *Binary,
    int: IntTerm,
    str: Str,
    boolean: Bool,
    call: *Call,
    print: *Print,
    tuple: *Tuple,
    nil: ?void,

    pub fn nil() Term {
        return Term{ .nil = null };
    }
};

pub const Int = i32;
