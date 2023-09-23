
#include <stdio.h>
#include <stdlib.h>

typedef enum { s = 0xca, i = 0xfe } Kind;

void p(void*v, Kind t) {
    switch(t) {
        case s:
            puts((char*)v);
            break;
        case i:
            printf("%d\n", *v);
            break;
    }
}
char* v_1 = "Hello world";
const Kind t_1 = 202;
int main(void) {
p((void*)v_1, t_1);
return 0;}
