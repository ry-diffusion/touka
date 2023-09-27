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

                    what => panic!("{} => Just ints. found {what:?}", $nm),
                }
            };
        }

        macro_rules! loveintcomp {
            ($it:expr, $binary:ident, $nm: expr, $op:tt) => {
                match (self.bag_or_die(*$binary.lhs.clone(), parent), self.bag_or_die(*$binary.rhs.clone(), parent)) {
                    (Term::Int(x), Term::Int(z)) => {
                        maybe!($it, x.value $op z.value);
                    }

                    _ => panic!(concat!($nm, "=> Just ints.")),
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

                let var = self
                    .variables
                    .get($b.text.as_str())
                    .expect("VARIABLE NOT FOUND VADIM.");
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

                let var = self
                    .variables
                    .get($b.text.as_str())
                    .expect("VARIABLE NOT FOUND VADIM.");
                let result = lazy!();

                push!("v_{result} = calloc(1024, sizeof(char));");
                push!("S(&v_{result},&t_{result}, (PSTR)&v_{var},(PSTR)&v_{rr},t_{var},s);",);
            }};
        }

        macro_rules! vitd {
            ($a:tt + $b:tt) => {{
                let rr = self.it;
                // phonk!(rr, $a.value);
                self.it += 1;

                let vara = self
                    .variables
                    .get($a.text.as_str())
                    .expect("VARIABLE NOT FOUND VADIM.");

                let var = self
                    .variables
                    .get($b.text.as_str())
                    .expect("VARIABLE NOT FOUND VADIM.");
                let result = lazy!();

                push!("v_{result} = calloc(1024, sizeof(char));");
                push!("S(&v_{result},&t_{result}, &v_{var},&v_{vara},t_{var},t_{vara});");
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

                    panic!("{}", res);
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
                    (Term::Var(v), Term::Int(i)) | (Term::Int(i), Term::Var(v)) => vitc!(i + v),
                    (Term::Var(v), Term::Var(v2)) => vitd!(v + v2),
                    (Term::Str(s), Term::Var(v)) | (Term::Var(v), Term::Str(s)) => vits!(s + v),

                    what => panic!("Add => Just ints and strings. found {what:?}"),
                },

                crate::ast::BinaryOp::Div => loveint!(self.it, binary, "Div", %),
                crate::ast::BinaryOp::Sub => loveint!(self.it, binary, "Sub", *),
                crate::ast::BinaryOp::Rem => loveint!(self.it, binary, "Rem", %),
                crate::ast::BinaryOp::Mul => loveint!(self.it, binary, "Mul", *),
                crate::ast::BinaryOp::Lt => loveintcomp!(self.it, binary, "Lt", <),
                crate::ast::BinaryOp::Gt => loveintcomp!(self.it, binary, "Gt", >),
                crate::ast::BinaryOp::Lte => loveintcomp!(self.it, binary, "Lte", >=),
                crate::ast::BinaryOp::Gte => loveintcomp!(self.it, binary, "Gte", <=),

                crate::ast::BinaryOp::Eq => match (*binary.lhs.clone(), *binary.rhs.clone()) {
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

                    _ => panic!("Eq => Invalid types!"),
                },

                crate::ast::BinaryOp::Neq => match (*binary.lhs.clone(), *binary.rhs.clone()) {
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

                    _ => todo!("neq"),
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

                    s => {
                        inspect!(&s);
                    }
                };

                self.variables.insert(r.name.text.clone(), self.it);
                inspect!(&r.next);
            }
            Term::Var(v) => {
                return *self.variables.get(&v.text).unwrap();
            }

            Term::Print(p) => {
                let it = inspect!(&p.value);

                self.print_queue.push(it);
            }

            _ => {}
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
