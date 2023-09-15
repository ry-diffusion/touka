// vi: ft=c

typedef unsigned char Boolean;
typedef int Num;
typedef char *Str;
typedef void *Lazy;

typedef struct workState {
  void *data;
} WorkState;

struct Tuple {
  void *first;
  void *second;
};

typedef void (*Function)(struct nUvWorkState *state);

/* Core libs */
extern void printStr(Str *out, Str content);
extern void printNum(Str *out, Num content);
extern void printBool(Str *out, Boolean content);
