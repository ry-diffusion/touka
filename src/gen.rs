use std::{collections::HashMap, error::Error, fs::File};

use std::io::Write;

type GenericResult<T> = Result<T, Box<dyn Error + Sync + Send>>;
use crate::ast::{Binary, File as AstRoot, Term};

const STR: u8 = 0xca;
const INT: u8 = 0xfe;
const MAYBE: u8 = 0xba;
const UNKNOWN: u8 = 0xbe;
const FN_MAIN: usize = 0x00;

#[derive(Default)]
pub struct State {
    constants: HashMap<usize, (String, String)>,
    types: HashMap<usize, u8>,
    print_queue: Vec<usize>,
    variables: HashMap<String, usize>,
    functions: Vec<usize>,
    named_functions: HashMap<String, usize>,
    scoped_variables: HashMap<usize, HashMap<String, usize>>,
    /* function ID, Queue of Evaluatiions */
    /* Of course, zero is main. */
    evaluation_queue: HashMap<usize, Vec<String>>,
    runtime_queue: HashMap<usize, String>,
    it: usize,
}

trait IsPure {
    fn is_pure(&self) -> bool;
}

impl IsPure for Term {
    fn is_pure(&self) -> bool {
        matches!(self, Term::Bool(_) | Term::Int(_) | Term::Str(_))
    }
}

impl State {
    fn bag_or_die(self: &mut Self, term: Term, parent: usize) -> Term {
        match term {
            Term::Print(p) => {
                let id = self.inspect(&p.value, parent);
                self.print_queue.push(id);
                self.it += 1;

                *p.value
            }

            _ => {
                self.inspect(&term, parent);

                term
            }
        }
    }

    fn inspect(self: &mut Self, term: &Term, parent: usize) -> usize {
        self.it += 1;

        // let mut inspect! = |term| self.inspect!(term, parent);
        // YOU DONT KNOW US TOO WELL, AT ALL.

        macro_rules! inspect {
            ($t:expr) => {
                self.inspect($t, parent)
            };
        }

        macro_rules! int {
            ($to:expr, $value:expr) => {{
                self.constants
                    .insert($to, ("int".to_string(), format!("{}", $value)));
                self.types.insert($to, INT);
            }};
        }

        macro_rules! maybe {
            ($to:expr, $value:expr) => {{
                self.constants
                    .insert($to, ("char".to_string(), format!("{}", $value)));
                self.types.insert($to, MAYBE);
            }};
        }

        macro_rules! loveint {
            ($it:expr, $binary:ident, $nm: expr, $op:tt) => {
                match (self.bag_or_die(*$binary.lhs.clone(), parent), self.bag_or_die(*$binary.rhs.clone(), parent)) {
                    (Term::Int(x), Term::Int(z)) => {
                        int!($it, x.value $op z.value);
                    }

                    (Term::Var(v), Term::Var(v2)) => vitao!(v, v2, $nm),
                    (Term::Var(v), Term::Int(i)) | (Term::Int(i), Term::Var(v)) => vitao!(known i, v, $nm),


                    what => panic!("{} => Just ints. found {what:?}", $nm),
                }
            };
        }

        macro_rules! ohyeahcomp {
            ($it:expr, $binary:ident, $nm: expr, $op:tt) => {
                match (self.bag_or_die(*$binary.lhs.clone(), parent), self.bag_or_die(*$binary.rhs.clone(), parent)) {
                    (Term::Int(x), Term::Int(z)) => {
                        maybe!($it, x.value $op z.value);
                    }

                    (Term::Var(v), Term::Var(v2)) => robertocomparacoes!(v, v2, $nm),
                    (Term::Var(v), Term::Int(i)) | (Term::Int(i), Term::Var(v)) => robertocomparacoes!(known i, v, $nm),

                    (Term::Var(v), Term::Str(i)) | (Term::Str(i), Term::Var(v)) => robertocomparacoes!(knownAsString i, v, $nm),

                    _ => panic!(concat!($nm, "=> Just ints or strings. With rules of course.")),
                }
            };
        }

        macro_rules! phonk {
            ($it:expr, $value:expr) => {{
                self.constants
                    .insert($it, ("char*".to_string(), format!("{:?}", $value)));
                self.types.insert($it, STR);
            }};
        }

        macro_rules! lazy {
            () => {{
                self.constants
                    .insert(self.it, ("void*".to_string(), "0".to_string()));
                self.types.insert(self.it, UNKNOWN);

                self.it
            }};

            (int) => {{
                self.constants
                    .insert(self.it, ("int*".to_string(), "0".to_string()));
                self.types.insert(self.it, INT);

                self.it
            }};

            (boolean) => {{
                self.constants
                    .insert(self.it, ("char*".to_string(), "0".to_string()));
                self.types.insert(self.it, MAYBE);

                self.it
            }};
        }

        macro_rules! push {
            ($($t:tt)*) => {{
                self.evaluation_queue.entry(parent).or_default().push(format!($($t)*));
            }};
        }

        macro_rules! vitc {
            ($a:tt + $b:tt) => {{
                let rr = self.it;
                self.it += 1;
                int!(rr, $a.value);

                let var = getvar!($b.text.as_str());
                let result = lazy!();

                push!("v_{result} = calloc(1, sizeof(char));");
                push!("S(&v_{result},&t_{result},&v_{var},&v_{rr},t_{var},i);",);
            }};
        }

        macro_rules! vits {
            ($a:tt + $b:tt) => {{
                let rr = self.it;
                phonk!(rr, $a.value);
                self.it += 1;

                let var = getvar!(&$b.text);
                let result = lazy!();

                push!("v_{result} = calloc(1024, sizeof(char));");
                push!("S(&v_{result},&t_{result}, (PSTR)&v_{var},(PSTR)&v_{rr},t_{var},s);",);
            }};
        }

        macro_rules! vitd {
            ($a:tt + $b:tt) => {{
                self.it += 1;

                let vara = getvar!(&$b.text);

                let var = getvar!(&$b.text);

                let result = lazy!(int);

                push!("v_{result} = calloc(1024, sizeof(char));");
                push!("S(&v_{result},&t_{result}, &v_{var},&v_{vara},t_{var},t_{vara});");
            }};
        }

        macro_rules! vitao {
            (known $a:tt, $b:tt, $nm:expr) => {{
                let rr = self.it;
                self.it += 1;
                int!(rr, $a.value);

                let var = getvar!($b.text.as_str());

                let result = lazy!(int);

                push!("v_{result} = calloc(1, sizeof(char));");
                push!(
                    "MathEvaluateA((int*)&v_{result},&v_{var},&v_{rr},t_{var},i, {});",
                    $nm
                );
            }};

            ($a:tt, $b:tt, $nm:expr) => {{
                self.it += 1;
                let result = lazy!(int);

                let vara = getvar!(&$b.text);
                let var = getvar!(&$b.text);

                push!("v_{result} = calloc(1, sizeof(int));");
                push!(
                    "MathEvaluateA((int*)&v_{result}, &v_{var},&v_{vara},t_{var},t_{vara}, {});",
                    $nm
                );
            }};
        }

        macro_rules! robertocomparacoes {
            (known $a:tt, $b:tt, $nm:expr) => {{
                let rr = self.it;
                self.it += 1;
                int!(rr, $a.value);

                let var = getvar!(&$b.text);
                let result = lazy!(boolean);

                push!("v_{result} = calloc(1, sizeof(char));");
                push!(
                    "BinaryEvaluateA((char*)&v_{result},&v_{var},&v_{rr},t_{var},i, {});",
                    $nm
                );
            }};

            (knownAsString $a:tt, $b:tt, $nm:expr) => {{
                let rr = self.it;
                self.it += 1;
                phonk!(rr, $a.value);

                let var = getvar!($b.text.as_str());
                let result = lazy!(boolean);

                push!("v_{result} = calloc(1, sizeof(char));");
                push!(
                    "BinaryEvaluateA((char*)&v_{result},&v_{var},&v_{rr},t_{var},i, {});",
                    $nm
                );
            }};

            ($a:tt, $b:tt, $nm:expr) => {{
                self.it += 1;
                let result = lazy!(boolean);

                let vara = getvar!($b.text.as_str());
                let var = getvar!($b.text.as_str());

                push!("v_{result} = calloc(1, sizeof(char));");
                push!(
                    "BinaryEvaluateA((char*)&v_{result}, &v_{var},&v_{vara},t_{var},t_{vara}, {});",
                    $nm
                );
            }};
        }

        macro_rules! getvar {
            ($name:expr) => {{
                let scoped = self
                    .scoped_variables
                    .entry(parent)
                    .or_default()
                    .get($name)
                    .map(|x| *x);

                let main = self
                    .scoped_variables
                    .entry(FN_MAIN)
                    .or_default()
                    .get($name)
                    .map(|x| *x);

                scoped
                    .or(main)
                    .expect(&format!("expected variable: <#var {parent}/{}>", $name))
            }};
        }

        match term {
            Term::Str(s) => {
                phonk!(self.it, s.value);
            }

            Term::Int(i) => {
                int!(self.it, i.value);
            }

            Term::If(comp) => match self.bag_or_die(*comp.condition.clone(), parent) {
                Term::Bool(b) => {
                    let res = if b.value {
                        inspect!(&comp.then)
                    } else {
                        inspect!(&comp.otherwise)
                    };

                    // panic!("{res}");
                }
                t @ Term::Binary(_) => {
                    let res = inspect!(&t);
                    if self.constants.get(&res).unwrap().1 == "true" {
                        inspect!(&comp.then)
                    } else {
                        inspect!(&comp.otherwise)
                    };
                }
                what => panic!("If => Just boolean or binary. found {what:?}"),
            },

            Term::Binary(binary) => match binary.op {
                crate::ast::BinaryOp::Add => match (
                    self.bag_or_die(*binary.lhs.clone(), parent),
                    self.bag_or_die(*binary.rhs.clone(), parent),
                ) {
                    (Term::Int(x), Term::Int(z)) => int!(self.it, x.value + z.value),
                    (Term::Str(s), Term::Str(s2)) => phonk!(self.it, s.value + &s2.value),
                    (Term::Var(v), Term::Var(v2)) => vitd!(v + v2),
                    (Term::Var(v), Term::Int(i)) | (Term::Int(i), Term::Var(v)) => vitc!(i + v),
                    (Term::Str(s), Term::Var(v)) | (Term::Var(v), Term::Str(s)) => vits!(s + v),

                    what => panic!("Add => Just ints and strings. found {what:?}"),
                },

                crate::ast::BinaryOp::Div => loveint!(self.it, binary, "Div", /),
                crate::ast::BinaryOp::Sub => loveint!(self.it, binary, "Sub", -),
                crate::ast::BinaryOp::Rem => loveint!(self.it, binary, "Rem", %),
                crate::ast::BinaryOp::Mul => loveint!(self.it, binary, "Mul", *),

                crate::ast::BinaryOp::Lt => ohyeahcomp!(self.it, binary, "Lt", <),
                crate::ast::BinaryOp::Gt => ohyeahcomp!(self.it, binary, "Gt", >),
                crate::ast::BinaryOp::Lte => ohyeahcomp!(self.it, binary, "Lte", >=),
                crate::ast::BinaryOp::Gte => ohyeahcomp!(self.it, binary, "Gte", <=),

                crate::ast::BinaryOp::Eq => match (
                    self.bag_or_die(*binary.lhs.clone(), parent),
                    self.bag_or_die(*binary.rhs.clone(), parent),
                ) {
                    (Term::Int(x), Term::Int(z)) => {
                        maybe!(self.it, x.value == z.value);
                    }

                    (Term::Str(s), Term::Str(s2)) => {
                        maybe!(self.it, s.value == s2.value);
                        // self.runtime_queue
                        //     .insert(self.it, format!("!strcmp({:?}, {:?})", s.value, s2.value));
                    }

                    (Term::Bool(b), Term::Bool(b2)) => {
                        maybe!(self.it, b.value == b2.value);
                    }

                    _ => ohyeahcomp!(self.it, binary, "Eq", ==),
                },

                crate::ast::BinaryOp::Neq => match (
                    self.bag_or_die(*binary.lhs.clone(), parent),
                    self.bag_or_die(*binary.rhs.clone(), parent),
                ) {
                    (Term::Int(x), Term::Int(z)) => {
                        maybe!(self.it, x.value != z.value);
                    }

                    (Term::Str(s), Term::Str(s2)) => {
                        maybe!(self.it, s.value != s2.value);
                        // self.runtime_queue
                        //     .insert(self.it, format!("!!strcmp({:?}, {:?})", s.value, s2.value));
                    }

                    (Term::Bool(b), Term::Bool(b2)) => {
                        maybe!(self.it, b.value != b2.value);
                    }

                    _ => ohyeahcomp!(self.it, binary, "Neq", ==),
                },

                crate::ast::BinaryOp::And => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Bool(b), Term::Bool(b2)) => {
                        maybe!(self.it, b.value && b2.value);
                    }

                    _ => panic!("Just bools are allowed."),
                },

                crate::ast::BinaryOp::Or => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Bool(b), Term::Bool(b2)) => {
                        maybe!(self.it, b.value || b2.value);
                    }

                    _ => panic!("Just bools are allowed."),
                },
            },

            Term::Let(r) => {
                match &*r.value {
                    Term::Str(s) => {
                        phonk!(self.it, s.value.clone());
                    }

                    Term::Int(i) => {
                        int!(self.it, i.value);
                    }

                    f @ Term::Function(_) => {
                        self.named_functions.insert(r.name.text.clone(), self.it);
                        inspect!(&f);
                    }

                    s => {
                        inspect!(&s);
                    }
                };

                self.scoped_variables
                    .entry(parent)
                    .or_default()
                    .insert(r.name.text.clone(), self.it);
                inspect!(&r.next);
            }

            Term::Tuple(t) => {
                let first = inspect!(&t.first);
                let second = inspect!(&t.second);
                self.it += 1;
                let rr = self.it;

                self.constants.insert(
                    rr,
                    (
                        "Tuple".to_string(),
                        format!("{{0}}"), // format!("{{v_{first},v_{second},t_{first},t_{second}}}"),
                    ),
                );

                push!("v_{rr}.a = &v_{first};");
                push!("v_{rr}.b = &v_{second};");
                push!("v_{rr}.ta = t_{first};");
                push!("v_{rr}.tb = t_{second};");

                self.types.insert(rr, 0x10);
            }

            Term::First(t) => match self.bag_or_die(*t.value.clone(), parent) {
                Term::Tuple(t) => {
                    inspect!(&t.first);
                }

                Term::Var(v) => {
                    let result = lazy!();

                    let var = getvar!(v.text.as_str());

                    push!("TupleIdxA(&v_{result}, &t_{result}, &v_{var}, t_{var}, 0);");
                }

                e => {
                    inspect!(&e);
                }
            },

            Term::Second(t) => match self.bag_or_die(*t.value.clone(), parent) {
                Term::Tuple(t) => {
                    inspect!(&t.second);
                }

                Term::Var(v) => {
                    let result = lazy!();

                    let var = getvar!(v.text.as_str());

                    push!("TupleIdxA(&v_{result}, &t_{result}, &v_{var}, t_{var}, 1);");
                }

                e => {
                    inspect!(&e);
                }
            },

            Term::Var(v) => {
                return getvar!(&v.text);
            }

            Term::Print(p) => {
                let it = inspect!(&p.value);

                self.print_queue.push(it);
            }

            Term::Function(f) => {
                self.functions.push(self.it);

                for param in f.parameters.iter() {
                    let id = lazy!();
                }

                self.inspect(&f.value, self.it);
            }

            e => eprintln!("ToukaGen: unimplemented {e:?}!"),
        }
        return self.it;
    }

    pub fn write(self: Self) -> GenericResult<()> {
        let mut output = File::create("output.c")?;

        writeln!(output, "{}", include_str!("yamero.c"))?;

        for (j, (k, v)) in self.constants {
            writeln!(output, "{} v_{} = {};", k, j, v)?
        }

        for (j, k) in self.types {
            writeln!(output, "Kind t_{j} = {k};")?;
        }

        for (j, k) in self.named_functions {
            writeln!(output, "fn: {j}")?;

            writeln!(output, "void f_{k}(void* r, ){{")?;

            if let Some(eq) = self.evaluation_queue.get(&k) {
                for item in eq {
                    writeln!(output, "{item}")?;
                }
            }

            writeln!(output, "}}")?;
        }

        writeln!(output, "int main(void) {{")?;

        for (id, expr) in self.runtime_queue {
            writeln!(output, "v_{id} = {expr};")?;
        }

        if let Some(eq) = self.evaluation_queue.get(&FN_MAIN) {
            for item in eq {
                writeln!(output, "{item}")?;
            }
        }

        for item in self.print_queue {
            writeln!(output, "p((void*)&v_{item}, t_{item});")?;
        }

        writeln!(output, "return 0;}}")?;

        Ok(())
    }

    pub fn generate(self: &mut Self, source: AstRoot) -> GenericResult<()> {
        self.inspect(&source.expression, FN_MAIN);
        // match source.expression {
        //     crate::ast::Term::Error(_) => todo!(),
        //     crate::ast::Term::Int(_) => todo!(),
        //     crate::ast::Term::Str(_) => todo!(),
        //     crate::ast::Term::Call(_) => todo!(),
        //     crate::ast::Term::Binary(_) => todo!(),
        //     crate::ast::Term::Function(_) => todo!(),
        //     t @ crate::ast::Term::Let(_) => {
        //         inspect!(&t);
        //     }
        //     crate::ast::Term::If(_) => todo!(),
        //     crate::ast::Term::Print(what) => {

        //     }
        //     crate::ast::Term::First(_) => todo!(),
        //     crate::ast::Term::Second(_) => todo!(),
        //     crate::ast::Term::Bool(_) => todo!(),
        //     crate::ast::Term::Tuple(_) => todo!(),
        //     crate::ast::Term::Var(_) => todo!(),
        // }

        Ok(())
    }
}
