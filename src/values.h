#ifndef VALUES_H
#define VALUES_H

#include "codegen.h" //para tener C3AType

/* struct para symtab.h */
typedef struct {
    C3AType type;
    int is_array; /* 1 si es array, 0 si es escalar */
    int length;   /* longitud declarada */
} value_info;

/* funciones auxiliares mínimas */
value_info* create_value(C3AType t, int is_array, int length);

#endif