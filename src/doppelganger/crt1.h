// vi: ft=c

typedef unsigned char Boolean;
typedef int Num;
typedef char *Str;

const Boolean E_1 = 1;
const Boolean E_2 = 0;

/* Core libs */
extern void printString(Str *out, Str content);
extern void printNum(Str *out, Num content);
extern void printBool(Str *out, Boolean content);
