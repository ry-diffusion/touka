
#include <stdio.h>
#include <stdlib.h>

typedef enum { s = 0xca, i = 0xfe } Kind;

void p(void*v, Kind t) {
    switch(t) {
        case s:
            puts((char*)v);
            break;
        case i:
            printf("%d\n", *(int*)v);
            break;
    }
}