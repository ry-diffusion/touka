// vi: ft=c
/* TR (Touka Runtime) declarations */
#ifndef TOUKA_H
#define TOUKA_H

/* Touka types */
typedef unsigned char Boolean;
typedef int Num;
typedef char *Str;
typedef void *Lazy;
typedef void *DpLoop;

const Lazy Unknown = 0;
typedef struct workState {
  void *data;
} WorkState;

typedef struct tuple {
  void *first;
  void *second;
} Tuple;

static DpLoop langLoop;
typedef void (*Function)(WorkState *state);

/* External libraries */
DpLoop tk_initLoop(void);
Num tk_run(DpLoop loop, int);

/* Core functions */
extern void tk_printStrComplex(Str *out, Str content);
extern void tk_printNumComplex(Num *out, Num content);
extern void tk_printBoolComplex(Boolean *out, Boolean content);
extern void tk_printStrNat(Str content);
extern void tk_printNumNat(Num *out, Num content);
extern void tk_printBoolNat(Boolean *out, Boolean content);
#endif

/* Finish TR declarations */
