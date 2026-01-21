#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"

#define MAX_QUADS 2000 /* Aumentamos límite para programas más grandes */

static int temp_counter = 1;
static Quad code_memory[MAX_QUADS];
static int next_quad = 1; /* empezar por línea 1 */

void cg_init() {
    temp_counter = 1;
    next_quad = 1;
}

int cg_next_quad() {
    return next_quad;
}

char* cg_new_temp() {
    char buffer[16];
    sprintf(buffer, "$t%02d", temp_counter++);
    return strdup(buffer);
}

void cg_emit(char *op, char *arg1, char *arg2, char *res) {
    if (next_quad >= MAX_QUADS) {
        fprintf(stderr, "Error: Límite de instrucciones excedido.\n");
        exit(1);
    }
    
    code_memory[next_quad].op = op ? strdup(op) : NULL;
    code_memory[next_quad].arg1 = arg1 ? strdup(arg1) : NULL;
    code_memory[next_quad].arg2 = arg2 ? strdup(arg2) : NULL;
    code_memory[next_quad].res = res ? strdup(res) : NULL;
    
    next_quad++;
}

void cg_print_all(FILE *out) {
    for (int i = 1; i < next_quad; i++) {
        Quad q = code_memory[i];
        fprintf(out, "%d: ", i);
        
        /* 1. Saltos y HALT */
        if (q.op && strncmp(q.op, "IF", 2) == 0) {
            /* Formato: IF x REL y GOTO L */
            /* El operador REL viene pegado o separado, ej "IFLT" o "IF LT" */
            /* Asumimos que parser envía "IF LT" o similar */
            /* Truco: Si op es "IF LTI", saltamos 3 chars para imprimir solo "LTI" */
            char *rel = q.op;
            if (strncmp(rel, "IF ", 3) == 0) rel += 3;
            else if (strncmp(rel, "IF", 2) == 0) rel += 2;
            
            fprintf(out, "IF %s %s %s GOTO %s\n", q.arg1, rel, q.arg2, q.res ? q.res : "???");
        }
        else if (q.op && strcmp(q.op, "GOTO") == 0) {
            fprintf(out, "GOTO %s\n", q.res ? q.res : "???");
        }
        else if (q.op && strcmp(q.op, "HALT") == 0) {
            fprintf(out, "HALT\n");
        }
        
        /* 2. Arrays */
        else if (q.op && strcmp(q.op, "arr_set") == 0) {
            fprintf(out, "%s[%s] := %s\n", q.arg1, q.arg2, q.res);
        }
        else if (q.op && strcmp(q.op, "arr_get") == 0) {
            fprintf(out, "%s := %s[%s]\n", q.res, q.arg1, q.arg2);
        }

        /* 3. Funciones */
        else if (q.op && strcmp(q.op, "PARAM") == 0) {
            fprintf(out, "PARAM %s\n", q.arg1);
        }
        else if (q.op && strcmp(q.op, "CALL") == 0) {
            fprintf(out, "CALL %s, %s\n", q.arg1, q.arg2);
        }

        /* 4. Asignación simple */
        else if (q.op && strcmp(q.op, ":=") == 0) {
            fprintf(out, "%s := %s\n", q.res, q.arg1);
        }

        /* 5. Operaciones Binarias */
        else if (q.arg1 && q.arg2 && q.res) {
            fprintf(out, "%s := %s %s %s\n", q.res, q.arg1, q.op, q.arg2);
        }

        /* 6. Unarios */
        else if (q.arg1 && q.res) {
            fprintf(out, "%s := %s %s\n", q.res, q.op, q.arg1);
        }
        
        else {
            /* Fallback genérico */
            fprintf(out, "%s %s %s %s\n", q.op, q.arg1 ? q.arg1 : "", q.arg2 ? q.arg2 : "", q.res ? q.res : "");
        }
    }
}

char* type_to_opcode(char *base_op, C3AType t) {
    static char buffer[16];
    char suffix = (t == T_FLOAT) ? 'F' : 'I';
    sprintf(buffer, "%s%c", base_op, suffix);
    return strdup(buffer);
}

/* --- IMPLEMENTACIÓN DE BACKPATCHING --- */

/* Crea una lista nueva con un solo índice */
ListNode* makelist(int i) {
    ListNode *node = (ListNode*)malloc(sizeof(ListNode));
    node->instr_idx = i;
    node->next = NULL;
    return node;
}

/* Fusiona dos listas */
ListNode* merge(ListNode *l1, ListNode *l2) {
    if (!l1) return l2;
    if (!l2) return l1;
    
    ListNode *p = l1;
    while (p->next != NULL) {
        p = p->next;
    }
    p->next = l2;
    return l1;
}

/* Rellena las instrucciones pendientes con la etiqueta destino */
void backpatch(ListNode *l, int label_idx) {
    char label_str[16];
    sprintf(label_str, "%d", label_idx);
    
    ListNode *current = l;
    while (current != NULL) {
        int idx = current->instr_idx;
        
        /* Verificación de seguridad */
        if (idx > 0 && idx < next_quad) {
            /* Liberamos el placeholder si existía y asignamos la etiqueta */
            if (code_memory[idx].res) free(code_memory[idx].res);
            code_memory[idx].res = strdup(label_str);
        }
        
        /* Avanzamos y liberamos el nodo de la lista (ya no sirve) */
        ListNode *temp = current;
        current = current->next;
        free(temp);
    }
}