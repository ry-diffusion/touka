use std::{collections::HashMap, error::Error, fs::File};

use std::io::Write;

type GenericResult<T> = Result<T, Box<dyn Error + Sync + Send>>;
use crate::ast::{File as AstRoot, Term};

const STR: u8 = 0xca;
const INT: u8 = 0xfe;
const MAYBE: u8 = 0xba;

#[derive(Default)]
pub struct State {
    constants: HashMap<usize, (String, String)>,
    types: HashMap<usize, u8>,
    print_queue: Vec<usize>,
    runtime_queue: HashMap<usize, String>,
    it: usize,
}

impl State {
    fn inspect(self: &mut Self, term: &Term) -> usize {
        self.it += 1;

        macro_rules! int {
            ($to:expr, $value:expr) => {
                {
                      self.constants
                    .insert($to, ("int".to_string(), format!("{}", $value)));
                self.types.insert($to, INT);
                }
            };
        }

        macro_rules! maybe {
            ($to:expr, $value:expr) => {
                {
                      self.constants
                    .insert($to, ("char".to_string(), format!("{}", $value)));
                self.types.insert($to, MAYBE);
                }
            };
        }

        match term {
            Term::Str(s) => {
            
                self.constants
                    .insert(self.it, ("char*".to_string(), format!("{:?}", s.value)));
                self.types.insert(self.it, STR);
            }

            Term::Int(i) => {
              int!(self.it, i.value);
            }

            Term::Binary(binary) => match binary.op {
                crate::ast::BinaryOp::Add => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                            int!(self.it, x.value + z.value);
                    }

                    _ => todo!(),
                },

                crate::ast::BinaryOp::Sub => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                        int!(self.it, x.value - z.value);
                    }

                    _ => todo!(),
                },

                crate::ast::BinaryOp::Div => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                        int!(self.it, x.value / z.value);
                    }

                    _ => todo!(),
                },
                
                crate::ast::BinaryOp::Mul => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                        int!(self.it, x.value * z.value);
                    }

                    _ => todo!(),
                },

                crate::ast::BinaryOp::Rem =>  match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                        int!(self.it, x.value % z.value);
                    }

                    _ => todo!(),
                },

                crate::ast::BinaryOp::Eq =>  match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                        maybe!(self.it, x.value == z.value);
                    }

                    (Term::Str(s), Term::Str(s2)) => {
                        maybe!(self.it, false);
                        self.runtime_queue.insert(self.it, format!("!strcmp({:?}, {:?})", s.value, s2.value));
                    },

                    (Term::Bool(b), Term::Bool(b2)) => {
                        maybe!(self.it, b.value == b2.value);
                    }

                    _ => todo!(),
                },

                crate::ast::BinaryOp::Neq => match (*binary.lhs.clone(), *binary.rhs.clone()) {
                    (Term::Int(x), Term::Int(z)) => {
                        maybe!(self.it, x.value != z.value);
                    },

                    (Term::Str(s), Term::Str(s2)) => {
                        maybe!(self.it, false);
                        self.runtime_queue.insert(self.it, format!("!!strcmp({:?}, {:?})", s.value, s2.value));
                    },

                    (Term::Bool(b), Term::Bool(b2)) => {
                        maybe!(self.it, b.value != b2.value);
                    }

                    _ => todo!(),
                },

                crate::ast::BinaryOp::Lt => todo!(),
                crate::ast::BinaryOp::Gt => todo!(),
                crate::ast::BinaryOp::Lte => todo!(),
                crate::ast::BinaryOp::Gte => todo!(),
                crate::ast::BinaryOp::And => todo!(),
                crate::ast::BinaryOp::Or => todo!()
            },

            _ => {}
        }
        return self.it;
    }

    pub fn write(mut self: Self) -> GenericResult<()> {
        let mut output = File::create("output.c")?;

        writeln!(output, "{}", include_str!("yamero.c"))?;

        for (j, (k, v)) in self.constants {
            writeln!(output, "{} v_{} = {};", k, j, v)?
        }

        for (j, k) in self.types {
            writeln!(output, "const Kind t_{j} = {k};")?;
        }

        writeln!(output, "int main(void) {{")?;

        for (id, expr) in self.runtime_queue {
            writeln!(output, "v_{id} = {expr};")?;
        }

        for item in self.print_queue {
            writeln!(output, "p((void*)&v_{item}, t_{item});")?;
        }

        writeln!(output, "return 0;}}")?;

        Ok(())
    }

    pub fn generate(self: &mut Self, source: AstRoot) -> GenericResult<()> {
        match source.expression {
            crate::ast::Term::Error(_) => todo!(),
            crate::ast::Term::Int(_) => todo!(),
            crate::ast::Term::Str(_) => todo!(),
            crate::ast::Term::Call(_) => todo!(),
            crate::ast::Term::Binary(_) => todo!(),
            crate::ast::Term::Function(_) => todo!(),
            crate::ast::Term::Let(_) => todo!(),
            crate::ast::Term::If(_) => todo!(),
            crate::ast::Term::Print(what) => {
                let it = self.inspect(&what.value);
                self.print_queue.push(it);
            }
            crate::ast::Term::First(_) => todo!(),
            crate::ast::Term::Second(_) => todo!(),
            crate::ast::Term::Bool(_) => todo!(),
            crate::ast::Term::Tuple(_) => todo!(),
            crate::ast::Term::Var(_) => todo!(),
        }

        Ok(())
    }
}
