
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define fnDecl(name, ...) void *name(void *tr, ##__VA_ARGS__)
#define panic(fmt, ...)                                                        \
  do {                                                                         \
    fprintf(stderr, "ToukaRT: " fmt, ##__VA_ARGS__);                           \
    exit(0);                                                                   \
  } while (0)

typedef enum MathOp { Sub = 0x99, Rem = 0x98, Mul = 0x97, Div = 0x96 } MathOp;

typedef enum Kind {
  s = 0xca,
  i = 0xfe,
  b = 0xba,
  u = 0xbe,
  kTuple = 0x10,
  kFunction = 0x42,
} Kind;

typedef enum BinaryOp { Lte = 1, Gte, Lt, Gt, Eq, Neq } BinaryOp;

typedef struct Tuple {
  void *a, *b;
  Kind ta, tb;
} Tuple;

typedef char **PSTR;
#define true 1
#define false 0

/* Print */
void pi(void *v, Kind t) {
  switch (t) {
  case s:
    printf("%s", *(char **)v);
    break;
  case i:
    printf("%d", *(int *)v);
    break;
  case u:
    printf("<#unknown>");
    break;
  case b:
    printf("%s", *(char *)v ? "true" : "false");
    break;
  case kTuple: {
    struct Tuple _t = *((Tuple *)v);
    printf("(");
    pi(_t.a, _t.ta);
    printf(", ");
    pi(_t.b, _t.tb);
    printf(")");
    break;
  }
  }
}

inline void p(void *v, Kind t) {
#ifdef dbg
  fprintf(stderr, "ToukaRT/IO/WriteStdout: v=%x, t=%x: ", v, t);
#endif

  pi(v, t);
  puts("");
}

/* Sum */
void S(void *r, Kind *t_r, void *a, void *b, Kind t_a, Kind t_b) {
  /* TODO: Use arrays. */
#ifdef dbg
  fprintf(stderr, "ToukaRT/Sum: %x + %x (?%p, ?%p) -> %p/%x\n", t_a, t_b, a, b,
          r, t_r);
#endif

  if (t_a == s && t_b == s)
    sprintf(*(char **)r, "%s%s", *(PSTR)a, *(PSTR)b);

  else if (t_a == s && t_b == i)
    sprintf(*(char **)r, "%s%d", *(PSTR)a, *(int *)b);

  else if (t_a == i && t_b == s)
    sprintf(*(char **)r, "%d%s", *(int *)a, *(PSTR)b);

  else if (t_a == i && t_b == i) {
    *(int *)r = *(int *)a + *(int *)b;
    *t_r = i;
    return;
  }

  else
    panic("Invalid sum between %x and %x. Aborting program exec.", t_a, t_b);

  *t_r = s;
}

/* Do the math  */
void BinaryEvaluateA(char *r, void *a, void *b, Kind t_a, Kind t_b, MathOp op) {
#define each(x, y)                                                             \
  case x:                                                                      \
    *(int *)r = *(int *)a y * (int *)b;                                        \
    break;

  if (t_a == i && t_a == t_b) {
    switch (op) {
      each(Eq, ==);
      each(Neq, !=);
      each(Gt, >);
      each(Lt, <);
      each(Gte, >=);
      each(Lte, <=);
    }
  }

  else if (t_a == s && t_a == t_b) {
    switch (op) {
    case Eq:
      *r = (0 == strcmp(*(PSTR)a, *(PSTR)b));
      break;

    case Neq:
      *r = (0 != strcmp(*(PSTR)a, *(PSTR)b));
      break;
    default:
      panic("String comparation doesn't support %x. Aborting program exec.",
            op);
    }
  }

  else
    panic("Invalid %x operation between %x and %x. Aborting program exec.", op,
          t_a, t_b);
#undef each
}

void MathEvaluateA(int *r, void *a, void *b, Kind t_a, Kind t_b, MathOp op) {
#define each(x, y)                                                             \
  case x:                                                                      \
    *r = *(int *)a y * (int *)b;                                               \
    break;

  if (t_a == i && t_a == t_b) {
    switch (op) {
      each(Sub, -);
      each(Div, /);
      each(Rem, %);
      each(Mul, *);
    }
  } else
    panic("Invalid %x operation between %x and %x. Aborting program exec.", op,
          t_a, t_b);
#undef each
}

void TupleIdxA(void **r, Kind *tR, void *t, Kind k, char idx) {
  if (k != kTuple)
    panic("I need a tuple blyat!");

  if (idx > 1)
    panic("Tuples have no more than 2 idx Vadim!");

  struct Tuple _t = *(Tuple *)t;

  if (!idx) {
    *r = *(void **)_t.a;
    *tR = _t.ta;
  } else {
    *r = *(void **)_t.b;
    *tR = _t.tb;
  }
}
