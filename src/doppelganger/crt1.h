// vi: ft=c

typedef unsigned char Boolean;
typedef int Num;
typedef char *Str;
typedef void *Lazy;

const Lazy None = 0;

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
extern void printStr(Str *out, Str content);
extern void printNum(Str *out, Num content);
extern void printBool(Str *out, Boolean content);
