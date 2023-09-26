
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum
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
  {
    fprintf(stderr, "ToukaRT: Invalid sum between %x and %x. Aborting program exec.", t_a, t_b);
    exit(1);
  }

  *t_r = s;
}