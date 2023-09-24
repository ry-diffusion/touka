
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { s = 0xca, i = 0xfe, b = 0xba } Kind;

#define true 1
#define false 0

void p(void *v, Kind t) {
  switch (t) {
  case s:
    puts(*(char **)v);
    break;
  case i:
    printf("%d\n", *(int *)v);
    break;
  case b:
    puts(*(char *)v ? "true" : "false");
    break;
  }
}
