
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define panic(fmt, ...)                              \
  do                                                 \
  {                                                  \
    fprintf(stderr, "ToukaRT: " fmt, ##__VA_ARGS__); \
    exit(0);                                         \
  } while (0)

typedef enum MathOp
{
  Sub = 0x99,
  Rem = 0x98,
  Mul = 0x97,
  Div = 0x96
} MathOp;

typedef enum Kind
{
  s = 0xca,
  i = 0xfe,
  b = 0xba,
  u = 0xbe,
} Kind;

typedef char **PSTR;
#define true 1
#define false 0

/* Print */
void p(void *v, Kind t)
{
#ifdef dbg
  fprintf(stderr, "ToukaRT/IO/WriteStdout: v=%x, t=%x: ", v, t);
#endif

  switch (t)
  {
  case s:
    puts(*(char **)v);
    break;
  case i:
    printf("%d\n", *(int *)v);
    break;
  case u:
    puts("<#unknown>");
    break;
  case b:
    puts(*(char *)v ? "true" : "false");
    break;
  }
}

/* Sum */
void S(void *r, Kind *t_r, void *a, void *b, Kind t_a, Kind t_b)
{
  /* TODO: Use arrays. */
#ifdef dbg
  fprintf(stderr, "ToukaRT/Sum: %x + %x (?%p, ?%p) -> %p/%x\n", t_a, t_b, a, b, r, t_r);
#endif

  if (t_a == s && t_b == s)
    sprintf(*(char **)r, "%s%s", *(PSTR)a, *(PSTR)b);

  else if (t_a == s && t_b == i)
    sprintf(*(char **)r, "%s%d", *(PSTR)a, *(int *)b);

  else if (t_a == i && t_b == s)
    sprintf(*(char **)r, "%d%s", *(int *)a, *(PSTR)b);

  else if (t_a == i && t_b == i)
  {
    *(int *)r = *(int *)a + *(int *)b;
    *t_r = i;
    return;
  }

  else
    panic("Invalid sum between %x and %x. Aborting program exec.", t_a, t_b);

  *t_r = s;
}

/* Do the math  */
void MathEvaluateA(int *r, void *a, void *b, Kind t_a, Kind t_b, MathOp op)
{
#define each(x, y)                      \
  case x:                               \
    *(int *)r = *(int *)a y * (int *)b; \
    break;

  if (t_a == i && t_a == t_b)
  {
    switch (op)
    {
      each(Sub, -);
      each(Div, /);
      each(Rem, %);
      each(Mul, *);
    }
  }
  else
    panic("Invalid %x operation between %x and %x. Aborting program exec.", op, t_a, t_b);
#undef each
}