#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdio.h>

typedef enum {
    T_INT,
    T_FLOAT,
    T_BOOL,
    T_STRING,
    T_ERROR
} C3AType;

/* --- ESTRUCTURA PARA BACKPATCHING --- */
/* Lista enlazada simple de enteros (índices de instrucciones) */
typedef struct list_node {
    int instr_idx;
    struct list_node *next;
} ListNode;

/* Estructura para subir info por el parser ($$) */
typedef struct {
    char *addr;     /* Dirección: "x", "$t1", "5" */
    C3AType type;   /* Tipo */
    
    char *ctr_var;  /* Offset para Arrays */
    
    /* BACKPATCHING */
    ListNode *truelist;   /* Saltos TRUE */
    ListNode *falselist;  /* Saltos FALSE */
    ListNode *nextlist;   /* Saltos de flujo normal (fin de bloque) */
    ListNode *breaklist;  /* Saltos de break */

    int label_idx;  /* Marcador M */
} C3A_Info;

/* Estructura de una instrucción C3A */
typedef struct {
    char *op;       /* Operación */
    char *arg1;     /* Operando 1 */
    char *arg2;     /* Operando 2 */
    char *res;      /* Resultado o Label de destino */
} Quad;

/* Funciones */
void cg_init();
char* cg_new_temp();
int cg_next_quad(); /* devuelve el número de la siguiente instrucción */

/* Emitir instrucciones */
void cg_emit(char *op, char *arg1, char *arg2, char *res);
void cg_print_all(FILE *out);

/* Helper de tipos */
char* type_to_opcode(char *base_op, C3AType t);

/* --- FUNCIONES PARA BACKPATCHING --- */
ListNode* makelist(int i);
ListNode* merge(ListNode *l1, ListNode *l2);
void backpatch(ListNode *l, int label_idx);

#endif