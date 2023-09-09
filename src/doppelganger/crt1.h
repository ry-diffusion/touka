// vi: ft=c

#ifndef DOPPELGANGER_VALUES
#define DOPPELGANGER_VALUES

typedef struct Object {
  void *ref;
  void (*sum)(struct Object *result, struct Object *a, struct Object *b);
} CoreObj;

#endif
