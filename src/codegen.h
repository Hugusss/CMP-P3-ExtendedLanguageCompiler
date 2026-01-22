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
    ListNode *truelist;
    ListNode *falselist;
    ListNode *nextlist;
    ListNode *breaklist;

    int label_idx;  /* Marcador M (inicio de bloque) */
    
    /* --- SOPORTE UNROLLING --- */
    int is_unrollable;  /* 1 si es literal pequeño */
    int unroll_count;   /* Cuántas veces repetir */
    int instr_start;    /* Dónde empieza el cuerpo */
} C3A_Info;

/* Estructura de una instrucción C3A */
typedef struct {
    char *op;       /* Operación */
    char *arg1;     /* Operando 1 */
    char *arg2;     /* Operando 2 */
    char *res;      /* Resultado o Label de destino */
} Quad;

/* Funciones de Gestión */
void cg_init();
char* cg_new_temp();
char* cg_new_label(); 
int cg_next_quad();

/* Emisión y Manipulación */
void cg_emit(char *op, char *arg1, char *arg2, char *res);
void cg_backpatch(ListNode *l, int label_idx);

/* --- FUNCIONES IMP. --- */
void cg_clone_code(int start_idx, int end_idx, int times); /* Unrolling */
void cg_dump_code(FILE *out); /* Volcar buffer a disco */

/* Helpers */
ListNode* makelist(int i);
ListNode* merge(ListNode *l1, ListNode *l2);
char* type_to_opcode(char *base_op, C3AType t);

/* Macro para compatibilidad */
#define backpatch cg_backpatch

#endif