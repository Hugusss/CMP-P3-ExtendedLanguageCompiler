#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "codegen.h"

#define MAX_QUADS 5000 /* Aumentado para soportar código duplicado */

static int temp_counter = 1;
static Quad code_memory[MAX_QUADS]; /* Buffer en RAM */
static int next_quad = 1; 

void cg_init() {
    temp_counter = 1;
    next_quad = 1;
}

int cg_next_quad() {
    return next_quad;
}

char* cg_new_temp() {
    char buffer[20];
    sprintf(buffer, "$t%02d", temp_counter++);
    return strdup(buffer);
}

void cg_emit(char *op, char *arg1, char *arg2, char *res) {
    if (next_quad >= MAX_QUADS) {
        fprintf(stderr, "Error Fatal: Buffer de instrucciones lleno (MAX %d).\n", MAX_QUADS);
        exit(1);
    }
    
    /* Guardamos COPIAS en el buffer */
    code_memory[next_quad].op = op ? strdup(op) : NULL;
    code_memory[next_quad].arg1 = arg1 ? strdup(arg1) : NULL;
    code_memory[next_quad].arg2 = arg2 ? strdup(arg2) : NULL;
    code_memory[next_quad].res = res ? strdup(res) : NULL;
    
    next_quad++;
}

/* --- FUNC LOOP UNROLLING --- */
void cg_clone_code(int start_idx, int end_idx, int times) {
    if (times <= 0) return;
    
    for (int t = 0; t < times; t++) {
        /* Desplazamiento actual respecto al original */
        int offset = next_quad - start_idx;
        
        for (int i = start_idx; i < end_idx; i++) {
            Quad src = code_memory[i];
            
            char *new_op = src.op ? strdup(src.op) : NULL;
            char *new_arg1 = src.arg1 ? strdup(src.arg1) : NULL;
            char *new_arg2 = src.arg2 ? strdup(src.arg2) : NULL;
            char *new_res = src.res ? strdup(src.res) : NULL;

            /* REAJUSTE DE ETIQUETAS: Si un salto apunta DENTRO del bloque copiado,
               hay que moverlo para que apunte dentro de la COPIA */
            if (new_res && (strcmp(new_op, "GOTO") == 0 || strncmp(new_op, "IF", 2) == 0)) {
                if (isdigit(new_res[0])) {
                    int target = atoi(new_res);
                    if (target >= start_idx && target < end_idx) {
                        char buff[20];
                        sprintf(buff, "%d", target + offset);
                        free(new_res);
                        new_res = strdup(buff);
                    }
                }
            }
            
            cg_emit(new_op, new_arg1, new_arg2, new_res);
            
            /* liberar temporales locales (cg_emit ya hizo su copia) */
            if (new_op) free(new_op);
            if (new_arg1) free(new_arg1);
            if (new_arg2) free(new_arg2);
            if (new_res) free(new_res);
        }
    }
}

void cg_dump_code(FILE *out) {
    for (int i = 1; i < next_quad; i++) {
        Quad q = code_memory[i];
        fprintf(out, "%d: ", i);
        
        if (q.op && strncmp(q.op, "IF", 2) == 0) {
            fprintf(out, "%s %s %s GOTO %s\n", q.op, q.arg1, q.arg2, q.res ? q.res : "???");
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
            fprintf(out, "%s %s %s %s\n", q.op ? q.op : "", q.arg1 ? q.arg1 : "", q.arg2 ? q.arg2 : "", q.res ? q.res : "");
        }
    }
}

/* --- BACKPATCHING --- */
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
    while (p->next != NULL) p = p->next;
    p->next = l2;
    return l1;
}

/* Rellena las instrucciones pendientes con la etiqueta destino */
void cg_backpatch(ListNode *l, int label_idx) {
    char label_str[20];
    sprintf(label_str, "%d", label_idx);
    ListNode *curr = l;
    while (curr != NULL) {
        int idx = curr->instr_idx;
        if (idx > 0 && idx < next_quad) {
            if (code_memory[idx].res) free(code_memory[idx].res);
            code_memory[idx].res = strdup(label_str);
        }
        ListNode *temp = curr;
        curr = curr->next;
        free(temp);
    }
}

char* type_to_opcode(char *base_op, C3AType t) {
    static char buffer[20];
    char suffix = (t == T_FLOAT) ? 'F' : 'I';
    sprintf(buffer, "%s%c", base_op, suffix);
    return strdup(buffer);
}