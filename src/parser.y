%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "codegen.h"
#include "symtab.h"
#include "values.h"

extern int yylex();
extern int yylineno;
extern char *yytext;
extern FILE *yyin;
extern FILE *flog; /* Variable global de log definida en main.c */

void yyerror(const char *s);

/* --- PILA PARA SWITCH (Soporte anidado) --- */
#define MAX_NEST 20
static char *switch_stack[MAX_NEST];
static int switch_sp = 0;

void switch_push(char *val) {
    if (switch_sp < MAX_NEST) switch_stack[switch_sp++] = strdup(val);
}

char *switch_peek() {
    if (switch_sp > 0) return switch_stack[switch_sp-1];
    return NULL;
}

void switch_pop() {
    if (switch_sp > 0) {
        free(switch_stack[--switch_sp]);
    }
}

/* Helpers */
void install_var(char *name, C3AType type, int is_array, int length) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) {
        fprintf(stderr, "Error semántico: '%s' ya existe.\n", name);
        return;
    }
    v = create_value(type, is_array, length);
    sym_enter(name, &v);
    if(flog) fprintf(flog, "Declarada variable: %s\n", name);
}

C3AType get_var_type(char *name) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) return v->type;
    return T_ERROR;
}

/* Helpers de inicialización */
void init_info(C3A_Info *info) {
    info->type = T_ERROR; info->addr = NULL; info->ctr_var = NULL;
    info->truelist = NULL; info->falselist = NULL; 
    info->nextlist = NULL; info->breaklist = NULL;
    info->is_unrollable = 0; info->unroll_count = 0;
}

/* --- GENERADORES DE CÓDIGO --- */
/* Aritmética */
C3A_Info gen_binary_op(char *op_base, C3A_Info a, C3A_Info b) {
    C3A_Info res; init_info(&res);
    if (a.type == T_ERROR || b.type == T_ERROR) return res;

    /* MODULO: Solo enteros */
    if (strcmp(op_base, "MOD") == 0) {
        if (a.type != T_INT || b.type != T_INT) {
            fprintf(stderr, "Error semántico: MOD solo con enteros.\n");
            return res;
        }
        res.type = T_INT; res.addr = cg_new_temp();
        cg_emit("MODI", a.addr, b.addr, res.addr);
        return res;
    }

    char *addr_a = a.addr; char *addr_b = b.addr;
    C3AType final_type = T_INT;

    if (a.type == T_FLOAT || b.type == T_FLOAT) {
        final_type = T_FLOAT;
        if (a.type == T_INT) {
            char *t = cg_new_temp(); cg_emit("I2F", a.addr, NULL, t); addr_a = t;
        }
        if (b.type == T_INT) {
            char *t = cg_new_temp(); cg_emit("I2F", b.addr, NULL, t); addr_b = t;
        }
    }
    res.type = final_type; res.addr = cg_new_temp();
    cg_emit(type_to_opcode(op_base, final_type), addr_a, addr_b, res.addr);
    return res;
}

/* Unario (Cambio de signo) */
C3A_Info gen_unary_op(C3A_Info a) {
    C3A_Info res; init_info(&res);
    if (a.type == T_ERROR) return res;

    res.type = a.type;
    res.addr = cg_new_temp();
    /* Operadors de cambio de signo: CHSI (Entero), CHSF (Real)  */
    char *opcode = (a.type == T_INT) ? "CHSI" : "CHSF";
    
    /* geneera: $t1 := CHSI i */
    cg_emit(opcode, a.addr, NULL, res.addr);
    return res;
}

C3A_Info gen_power(C3A_Info base, C3A_Info exp) {
    C3A_Info res; init_info(&res);
    if (base.type == T_ERROR || exp.type == T_ERROR) return res;
    if (exp.type != T_INT) { fprintf(stderr, "Error: Exp debe ser entero.\n"); return res; }

    res.type = base.type; res.addr = cg_new_temp();
    /* Implementación naive: Bucle explícito */
    cg_emit(":=", (base.type==T_INT)?"1":"1.0", NULL, res.addr);

    char *cnt = cg_new_temp(); cg_emit(":=", "0", NULL, cnt);
    int start = cg_next_quad();
    char l_start[16], l_end[16]; sprintf(l_start, "%d", start); sprintf(l_end, "%d", start+4);
    
    cg_emit((exp.type==T_INT)?"IF GEI":"IF GEF", cnt, exp.addr, l_end);
    cg_emit((base.type==T_INT)?"MULI":"MULF", res.addr, base.addr, res.addr);
    cg_emit("ADDI", cnt, "1", cnt);
    cg_emit("GOTO", NULL, NULL, l_start);
    return res;
}

/* Relacionales */
C3A_Info gen_relational_op(char *rel_op, C3A_Info a, C3A_Info b) {
    C3A_Info res; init_info(&res);
    if (a.type == T_STRING || b.type == T_STRING) {
        fprintf(stderr, "Error: Comparación de strings no soportada.\n");
        return res;
    }
    
    char *addr_a = a.addr; char *addr_b = b.addr; char suffix = 'I';
    if (a.type == T_FLOAT || b.type == T_FLOAT) {
        suffix = 'F';
        if (a.type == T_INT) { char *t = cg_new_temp(); cg_emit("I2F", a.addr, NULL, t); addr_a = t; }
        if (b.type == T_INT) { char *t = cg_new_temp(); cg_emit("I2F", b.addr, NULL, t); addr_b = t; }
    }

    res.type = T_BOOL;
    res.truelist = makelist(cg_next_quad());
    char op[16]; sprintf(op, "IF %s%c", rel_op, suffix);
    cg_emit(op, addr_a, addr_b, NULL);
    res.falselist = makelist(cg_next_quad());
    cg_emit("GOTO", NULL, NULL, NULL);
    return res;
}
%}

%union {
    struct { char *lexema; int line; } ident;
    char *literal; 
    C3A_Info info;
}

%token ASSIGN PLUS MINUS MULT DIV MOD POW
%token LPAREN RPAREN LBRACE RBRACE SEMICOLON COLON COMMA DOT EOL
%token LBRACKET RBRACKET RANGE
%token KW_INT KW_FLOAT KW_STRING KW_BOOL STRUCT REPEAT DO DONE
%token KW_SIN KW_COS KW_TAN KW_LEN KW_SUBSTR
%token <literal> LIT_INT LIT_FLOAT LIT_STRING

%token IF THEN ELSE FI WHILE UNTIL FOR IN BREAK SWITCH CASE DEFAULT FSWITCH
%token AND OR NOT
%token EQ NEQ GT GE LT LE
%token <literal> LIT_BOOL

%token <ident> ID 

/* --- GRAMÁTICA ESTRATIFICADA --- */
%type <info> programa lista_sentencias sentencia
%type <info> declaracion asignacion
%type <info> expression bool_term bool_factor relation arith_expr term factor atom
%type <info> M N case_list case_item default_opt

%start programa

%%

programa : { cg_init(); if(flog) fprintf(flog, "Inicio del parseo\n"); } 
           lista_sentencias 
           { 
                cg_emit("HALT", NULL, NULL, NULL);
                if(flog) fprintf(flog, "Fin del parseo. Generando código...\n");
           }
         ;

lista_sentencias : /* vacio */ { $$.nextlist = NULL; $$.breaklist = NULL; }
                 | lista_sentencias M sentencia { 
                     /* BACKPATCHING: Rellenar saltos pendientes de sentencias anteriores */
                     backpatch($1.nextlist, $2.label_idx);
                     $$.nextlist = $3.nextlist;
                     $$.breaklist = merge($1.breaklist, $3.breaklist);
                 }
                 | lista_sentencias EOL { $$ = $1; }
                 ;

sentencia : declaracion EOL { $$.nextlist = NULL; $$.breaklist = NULL; }
          | asignacion EOL  { $$.nextlist = NULL; $$.breaklist = NULL; }
          | expression EOL { 
               cg_emit("PARAM", $1.addr, NULL, NULL);
               if ($1.type == T_FLOAT) cg_emit("CALL", "PUTF", "1", NULL);
               else cg_emit("CALL", "PUTI", "1", NULL);
               $$.nextlist = NULL; $$.breaklist = NULL;
            }
          | BREAK { 
               /* El break genera un salto que NO va al nextlist normal, sino al breaklist */
               $$.breaklist = makelist(cg_next_quad());
               cg_emit("GOTO", NULL, NULL, NULL);
               $$.nextlist = NULL;
            }
          /* --- IF --- */
          | IF expression THEN M lista_sentencias FI {
              backpatch($2.truelist, $4.label_idx);
                /* Si es FALSE, salta al final (FI) */
              $$.nextlist = merge($2.falselist, $5.nextlist);
              $$.breaklist = $5.breaklist; /* Propagar breaks internos */
          }
          | IF expression THEN M lista_sentencias N ELSE M lista_sentencias FI {
              backpatch($2.truelist, $4.label_idx);
                /* FALSE -> bloque ELSE */
              backpatch($2.falselist, $8.label_idx);
                /* Salida -> unión de salidas THEN (N) y ELSE */
              /* N genera un GOTO al final para saltarse el ELSE */
              ListNode *temp = merge($5.nextlist, $6.nextlist); /* nextlist de sentencia + GOTO N */
              $$.nextlist = merge(temp, $9.nextlist);
              $$.breaklist = merge($5.breaklist, $9.breaklist);
          }
          /* --- REPEAT con UNROLLING --- */
          | REPEAT arith_expr DO 
          {
              /* $4: Check optimización */
              if (isdigit($2.addr[0])) {
                  int val = atoi($2.addr);
                  if (val > 0 && val <= 5) {
                      $<info>$.is_unrollable = 1;
                      $<info>$.unroll_count = val;
                      $<info>$.instr_start = cg_next_quad(); /* Marca inicio cuerpo */
                      if(flog) fprintf(flog, "OPT: Loop Unrolling detectado (%d iters)\n", val);
                  } else {
                      $<info>$.is_unrollable = 0;
                  }
              } else {
                  /* Variable normal */
                  $<info>$.is_unrollable = 0;
                  char *cnt = cg_new_temp();
                  cg_emit(":=", $2.addr, NULL, cnt);
                  $<info>$.addr = cnt;
              }
          }
          M /* $5: Etiqueta inicio (solo si no hay unrolling) */
          {
              /* $6: Condición (solo si no hay unrolling) */
              if (!$<info>4.is_unrollable) {
              $<info>$.falselist = makelist(cg_next_quad());
              cg_emit("IF LEI", $<info>4.addr, "0", NULL);
          }
          }
          lista_sentencias /* $7 */
          DONE /* $8 */
          {
              if ($<info>4.is_unrollable) {
                  /* UNROLLING: Clonar código */
                  int end = cg_next_quad();
                  int times = $<info>4.unroll_count;
                  /* El cuerpo ya está escrito 1 vez, se clona (times-1) veces */
                  cg_clone_code($<info>4.instr_start, end, times - 1);
                  
                  $$.nextlist = $7.nextlist; 
                  $$.breaklist = $7.breaklist;
              } else {
                  /* NORMAL */
                  char *cnt = $<info>4.addr;
                  cg_emit("SUBI", cnt, "1", cnt);
                  char str_label[16]; sprintf(str_label, "%d", $5.label_idx);
              cg_emit("GOTO", NULL, NULL, str_label);
              
              /* Backpatch salida (La lista false esta en la acción $6) */
              backpatch($<info>6.falselist, cg_next_quad());
                  $$.nextlist = $7.nextlist;
                  $$.breaklist = $7.breaklist;
              }
          }
          | WHILE M expression DO M lista_sentencias DONE {
              backpatch($6.nextlist, $2.label_idx);
              backpatch($3.truelist, $5.label_idx);
              char s[16]; sprintf(s, "%d", $2.label_idx);
              cg_emit("GOTO", NULL, NULL, s);
              $$.nextlist = merge($3.falselist, $6.breaklist);
              $$.breaklist = NULL;
          }
          /* --- SWITCH --- */
          /* 1:SWITCH 2:( 3:expr 4:) 5:opt_eol 6:push 7:case_list 8:FSWITCH */
          | SWITCH LPAREN expression RPAREN opt_eol {
              switch_push($3.addr);
          } case_list FSWITCH {
              switch_pop();
              backpatch($7.falselist, cg_next_quad());
              $$.nextlist = merge($7.nextlist, $7.breaklist);
              $$.breaklist = NULL;
          }
          | FOR ID IN arith_expr RANGE arith_expr DO {
              if ($4.type != T_INT || $6.type != T_INT) yyerror("Rango FOR entero");
              cg_emit(":=", $4.addr, NULL, $2.lexema);
          } M {
              $<info>$.falselist = makelist(cg_next_quad());
              cg_emit("IF GTI", $2.lexema, $6.addr, NULL); 
          } lista_sentencias DONE {
              cg_emit("ADDI", $2.lexema, "1", $2.lexema);
              char s[16]; sprintf(s, "%d", $9.label_idx);
              cg_emit("GOTO", NULL, NULL, s);
              backpatch($<info>10.falselist, cg_next_quad());
              $$.nextlist = $11.breaklist; $$.breaklist = NULL;
          }
          | error EOL { yyerrok; $$.nextlist = NULL; $$.breaklist = NULL; }
          ;

/* --- EXPRESIONES ESTRATIFICADAS --- */
/* Nivel 1: OR */
expression : bool_term { $$ = $1; }
           | expression OR M bool_term {
               backpatch($1.falselist, $3.label_idx);
               $$.truelist = merge($1.truelist, $4.truelist);
               $$.falselist = $4.falselist;
               $$.type = T_BOOL;
           }
           ;

/* Nivel 2: AND */
bool_term : bool_factor { $$ = $1; }
          | bool_term AND M bool_factor {
              backpatch($1.truelist, $3.label_idx);
              $$.truelist = $4.truelist;
              $$.falselist = merge($1.falselist, $4.falselist);
              $$.type = T_BOOL;
          }
          ;

/* Nivel 3: NOT y Relacionales */
bool_factor : relation { $$ = $1; }
            | NOT bool_factor {
                $$.truelist = $2.falselist;
                $$.falselist = $2.truelist;
                $$.type = T_BOOL;
            }
            ;

relation : arith_expr { $$ = $1; }
         | arith_expr EQ arith_expr { $$ = gen_relational_op("EQ", $1, $3); }
         | arith_expr NEQ arith_expr { $$ = gen_relational_op("NE", $1, $3); }
         | arith_expr GT arith_expr { $$ = gen_relational_op("GT", $1, $3); }
         | arith_expr GE arith_expr { $$ = gen_relational_op("GE", $1, $3); }
         | arith_expr LT arith_expr { $$ = gen_relational_op("LT", $1, $3); }
         | arith_expr LE arith_expr { $$ = gen_relational_op("LE", $1, $3); }
         | LIT_BOOL {
             init_info(&$$); $$.type = T_BOOL;
             if (strcmp($1, "1")==0) { $$.truelist=makelist(cg_next_quad()); cg_emit("GOTO",NULL,NULL,NULL); }
             else { $$.falselist=makelist(cg_next_quad()); cg_emit("GOTO",NULL,NULL,NULL); }
         }
         ;

/* Nivel 4: Suma/Resta */
arith_expr : term { $$ = $1; }
           | arith_expr PLUS term { $$ = gen_binary_op("ADD", $1, $3); }
           | arith_expr MINUS term { $$ = gen_binary_op("SUB", $1, $3); }
           ;

/* Nivel 5: Mult/Div/Mod */
term : factor { $$ = $1; }
     | term MULT factor { $$ = gen_binary_op("MUL", $1, $3); }
     | term DIV factor { $$ = gen_binary_op("DIV", $1, $3); }
     | term MOD factor { $$ = gen_binary_op("MOD", $1, $3); }
     ;

/* Nivel 6: Potencia (Right associative) y MENOS UNARIO */
factor : atom { 
            /* Si es un acceso a array (R-Value), cargar el valor ahora */
           if ($1.ctr_var != NULL) {
               char *t = cg_new_temp();
               cg_emit("arr_get", $1.addr, $1.ctr_var, t);
               init_info(&$$);
               $$.addr = t;        /* Ahora trabajar con el valor temporal */
               $$.type = $1.type;
               $$.ctr_var = NULL;  /* Ya no es una referencia */
           } else {
               $$ = $1; 
           }
       }
       | atom POW factor {
           C3A_Info base = $1;
           if (base.ctr_var != NULL) {
               char *t = cg_new_temp();
               cg_emit("arr_get", base.addr, base.ctr_var, t);
               base.addr = t;
               base.ctr_var = NULL;
           }
           $$ = gen_power(base, $3); 
       }
       | MINUS factor { $$ = gen_unary_op($2); }
       ;

/* Nivel 7: Átomos */
atom : LIT_INT { init_info(&$$); $$.addr = strdup($1); $$.type = T_INT; }
     | LIT_FLOAT { init_info(&$$); $$.addr = strdup($1); $$.type = T_FLOAT; }
     | ID {
         init_info(&$$); $$.addr = strdup($1.lexema); $$.type = get_var_type($1.lexema);
     }
     | ID LBRACKET arith_expr RBRACKET {
         init_info(&$$);
         char *off = cg_new_temp(); cg_emit("MULI", $3.addr, "4", off);
         char *final = cg_new_temp(); cg_emit("ADDI", off, "25", final);
         $$.addr = strdup($1.lexema); $$.type = get_var_type($1.lexema);
         $$.ctr_var = final;
     }
     | LPAREN expression RPAREN { $$ = $2; }
     ;

/* --- OTRAS REGLAS AUXILIARES --- */
opt_eol : | opt_eol EOL ;

case_list : case_item case_list {
              $$.nextlist = merge($1.nextlist, $2.nextlist);
              $$.breaklist = merge($1.breaklist, $2.breaklist);
              backpatch($1.falselist, $2.label_idx);
              $$.falselist = $2.falselist; $$.label_idx = $1.label_idx;
          }
          | default_opt { $$ = $1; }
          ;
case_item : CASE arith_expr COLON {
               char *ctrl = switch_peek();
               
               /* guardar en $<info>$ los datos para recuperarlos luego */
               /* label_idx: Dónde empieza este caso (para que el anterior salte aquí) */
               $<info>$.label_idx = cg_next_quad();
               
               /* falselist: Lista de saltos si el caso NO coincide */
               $<info>$.falselist = makelist(cg_next_quad());
               cg_emit("IF NEQ", ctrl, $2.addr, NULL); 
            } lista_sentencias {
               /* ACCIÓN FINAL: recuperar los datos de la acción incrustada ($4) */
               $$.label_idx = $<info>4.label_idx; 
               $$.falselist = $<info>4.falselist; 
               
               /* Propagar los datos del cuerpo ($5) */
               $$.nextlist = $5.nextlist;
               $$.breaklist = $5.breaklist;
            }
            ;
default_opt : DEFAULT COLON M lista_sentencias {
                $$.label_idx = $3.label_idx; $$.nextlist = $4.nextlist;
                $$.breaklist = $4.breaklist; $$.falselist = NULL;
            }
            | { $$.label_idx = cg_next_quad(); $$.nextlist = NULL; $$.breaklist = NULL; 
                $$.falselist = makelist(cg_next_quad()); }
            ;
M : { $$.label_idx = cg_next_quad(); };
N : { $$.nextlist = makelist(cg_next_quad()); cg_emit("GOTO", NULL, NULL, NULL); };

declaracion : KW_INT ID { install_var($2.lexema, T_INT, 0, 0); }
            | KW_FLOAT ID { install_var($2.lexema, T_FLOAT, 0, 0); }
            | KW_BOOL ID { install_var($2.lexema, T_BOOL, 0, 0); }
            | KW_INT ID LBRACKET LIT_INT RBRACKET { install_var($2.lexema, T_INT, 1, atoi($4)); }
            ;
asignacion : atom ASSIGN expression {
                if ($1.ctr_var == NULL) cg_emit(":=", $3.addr, NULL, $1.addr);
                else cg_emit("arr_set", $1.addr, $1.ctr_var, $3.addr);
             }
           ;

%%
void yyerror(const char *s) {
    fprintf(stderr, "Error sintáctico línea %d: %s\n", yylineno, s);
    if(flog) fprintf(flog, "Error sintáctico línea %d: %s\n", yylineno, s);
}