const t = @import("doppelganger/types.zig");

pub const TermKind = enum {
    Int,
    Str,
    Call,
    Binary,
    Function,
    Let,
    If,
    Print,
    First,
    Second,
    Bool,
    Tuple,
    Var,
};

pub const BinaryOp = enum { Add, Sub, Mul, Div, Rem, Eq, Neq, Lt, Gt, Lte, Gte, And, Or };

pub const Term = union {
    kind: TermKind,
};

// Nodes
pub const File = struct {
    name: t.String,
    location: Loc,
    expression: Term,
};
pub const Loc = struct { start: t.Int, end: t.Int, filename: t.String };
pub const If = struct { kind: t.String, condition: Term, then: Term, otherwise: Term, location: Loc };

// types
pub const Str = struct { kind: t.String, value: t.String, location: Loc };
pub const Bool = struct { kind: t.String, value: bool, location: Loc };
pub const Int = struct { kind: t.String, value: t.Int, location: Loc };

pub const Parameter = struct { kind: TermKind, location: Loc };

// impurities
pub const Binary = struct { kind: t.String, lhs: Term, rhs: Term, op: BinaryOp, location: Loc };
pub const Call = struct { kind: t.String, calle: Term, arguments: []Term, location: Loc };
pub const Function = struct { kind: t.String, parameters: []Parameter, value: Term, location: Loc };
pub const Var = struct {
    kind: t.String,
    text: t.String,
    location: Loc,
};

// native functions
pub const Print = struct { kind: t.String, value: Term, location: Loc }; // Os valores devem ser printados como:

// Tipo	Como deve ser printado
// String	a string sem aspas duplas ex a
// Number	o literal de número ex 0
// Boolean	true ou false
// Closure	<#closure>
// Tuple	(term, term)

pub const First = struct { kind: t.String, value: Term, location: Loc };
pub const Second = struct { kind: t.String, value: Term, location: Loc };
pub const Tuple = struct {
    kind: t.String,
    first: Term, // Required
    second: Term, // Required: RuntimeException
    location: Loc,
};
