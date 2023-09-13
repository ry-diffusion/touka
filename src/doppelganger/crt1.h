// vi: ft=c

typedef unsigned char Boolean;
typedef int Num;
typedef char *Str;

static const Boolean E_1 = 1;
static const Boolean E_2 = 0;

struct nUvWorkState {
  void *data;
};

struct Tuple {
  void *first;
  void *second;
};

typedef void (*Function)(struct nUvWorkState *state);

/* Core libs */
extern void printString(Str *out, Str content);
extern void printNum(Str *out, Num content);
extern void printBool(Str *out, Boolean content);
