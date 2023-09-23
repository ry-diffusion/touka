
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


typedef enum { s = 0xca, i = 0xfe, b = 0xba } Kind;

#define true 1
#define false 0

void p(void*v, Kind t) {
    switch(t) {
        case s:
            puts(*(char**)v);
            break;
        case i:
            printf("%d\n", *(int*)v);
            break;
        case b: {
            char* bb = (char*)v;

            switch (*bb) {
                case 1:
                    puts("true");
                    break;
                case 0:
                    puts("false");
                    break;
            }
        }
    }
}
char v_1 = false;
const Kind t_1 = 186;
int main(void) {
v_1 = !strcmp("sim", "sim");
p((void*)&v_1, t_1);
return 0;}
