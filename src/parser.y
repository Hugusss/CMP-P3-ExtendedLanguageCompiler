%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "codegen.h"
#include "symtab.h"
#include "values.h"

extern int yylex();
extern int yylineno;
extern char *yytext;
extern FILE *yyin;

void yyerror(const char *s);

/* --- GESTIÓN DE VARIABLES --- */
void install_var(char *name, C3AType type, int is_array, int length) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) {
        fprintf(stderr, "Error semántico: '%s' ya existe.\n", name);
        return;
    }
    v = create_value(type, is_array, length);
    sym_enter(name, &v);
}

C3AType get_var_type(char *name) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) return v->type;
    return T_ERROR;
}

int is_var_array(char *name) {
    value_info *v;
    if (sym_lookup(name, &v) == SYMTAB_OK) return v->is_array;
    return 0;
}

/* --- PILA PARA SWITCH --- */
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
    if (switch_sp > 0) free(switch_stack[--switch_sp]);
}

/* --- HELPERS --- */
void init_info(C3A_Info *info) {
    info->type = T_ERROR; info->addr = NULL; info->ctr_var = NULL;
    info->truelist = NULL; info->falselist = NULL; 
    info->nextlist = NULL; info->breaklist = NULL;
}

C3A_Info gen_binary_op(char *op_base, C3A_Info a, C3A_Info b) {
    C3A_Info res; init_info(&res);

    if (a.type == T_ERROR || b.type == T_ERROR) return res;

    /* MODULO: Solo enteros */
    if (strcmp(op_base, "MOD") == 0) {
        if (a.type == T_FLOAT || b.type == T_FLOAT) {
            fprintf(stderr, "Error semántico: Módulo solo acepta enteros.\n");
            return res;
        }
        res.type = T_INT;
        res.addr = cg_new_temp();
        cg_emit("MODI", a.addr, b.addr, res.addr);
        return res;
    }

    /* Conversiones implícitas */
    char *addr_a = a.addr;
    char *addr_b = b.addr;
    C3AType final_type = T_INT;

    if (a.type == T_FLOAT || b.type == T_FLOAT) {
        final_type = T_FLOAT;
        if (a.type == T_INT) {
            char *temp = cg_new_temp();
            cg_emit("I2F", a.addr, NULL, temp);
            addr_a = temp;
        }
        if (b.type == T_INT) {
            char *temp = cg_new_temp();
            cg_emit("I2F", b.addr, NULL, temp);
            addr_b = temp;
        }
    }

    res.type = final_type;
    res.addr = cg_new_temp();
    cg_emit(type_to_opcode(op_base, final_type), addr_a, addr_b, res.addr);
    return res;
}

C3A_Info gen_unary_op(C3A_Info a) {
    C3A_Info res; init_info(&res);
    if (a.type == T_ERROR) return res;

    res.type = a.type;
    res.addr = cg_new_temp();
    char *opcode = (a.type == T_INT) ? "CHSI" : "CHSF";
    cg_emit(opcode, a.addr, NULL, res.addr);
    return res;
}

C3A_Info gen_power(C3A_Info base, C3A_Info exp) {
    C3A_Info res; init_info(&res);

    if (base.type == T_ERROR || exp.type == T_ERROR) return res;
    if (exp.type != T_INT) {
        fprintf(stderr, "Error semántico: Exponente debe ser entero.\n");
        return res;
    }

    res.type = base.type; 
    res.addr = cg_new_temp();
    if (base.type == T_INT) cg_emit(":=", "1", NULL, res.addr);
    else cg_emit(":=", "1.0", NULL, res.addr);

    char *cnt = cg_new_temp();
    cg_emit(":=", "0", NULL, cnt);

    int start_label_idx = cg_next_quad();
    char start_label[16]; sprintf(start_label, "%d", start_label_idx);
    
    int end_label_idx = start_label_idx + 4;
    char end_label[16]; sprintf(end_label, "%d", end_label_idx);
    
    char *rel_op = (exp.type == T_INT) ? "GEI" : "GEF";
    char if_op[16]; sprintf(if_op, "IF %s", rel_op);
    
    cg_emit(if_op, cnt, exp.addr, end_label);
    
    char *op = (base.type == T_INT) ? "MULI" : "MULF";
    cg_emit(op, res.addr, base.addr, res.addr);
    cg_emit("ADDI", cnt, "1", cnt);
    cg_emit("GOTO", NULL, NULL, start_label);

    return res;
}

C3A_Info gen_relational_op(char *rel_op, C3A_Info a, C3A_Info b) {
    C3A_Info res;
    init_info(&res);
    
    if (a.type == T_STRING || b.type == T_STRING) {
        fprintf(stderr, "Error semántico: No se pueden comparar cadenas.\n");
        return res; // Devuelve error
    }
    
    res.type = T_BOOL;
    
    char *addr_a = a.addr;
    char *addr_b = b.addr;
    char suffix = 'I'; /* Por defecto enteros */

    if (a.type == T_FLOAT || b.type == T_FLOAT) {
        suffix = 'F';
        if (a.type == T_INT) {
            char *temp = cg_new_temp();
            cg_emit("I2F", a.addr, NULL, temp);
            addr_a = temp;
        }
        if (b.type == T_INT) {
            char *temp = cg_new_temp();
            cg_emit("I2F", b.addr, NULL, temp);
            addr_b = temp;
        }
    }

    /* Generar: IF x REL y GOTO (hueco truelist) */
    res.truelist = makelist(cg_next_quad());
    char op_full[16];
    sprintf(op_full, "IF %s%c", rel_op, suffix);
    cg_emit(op_full, addr_a, addr_b, NULL);
    
    res.falselist = makelist(cg_next_quad());
    cg_emit("GOTO", NULL, NULL, NULL);

    return res;
}
%}

%union {
    struct {
        char *lexema;
        int line;
    } ident;
    char *literal; 
    C3A_Info info;
}

%token ASSIGN PLUS MINUS MULT DIV MOD POW
%token LPAREN RPAREN LBRACE RBRACE SEMICOLON COLON COMMA DOT EOL
%token LBRACKET RBRACKET RANGE
%token KW_INT KW_FLOAT KW_STRING KW_BOOL STRUCT REPEAT DO DONE
%token KW_SIN KW_COS KW_TAN KW_LEN KW_SUBSTR
%token <literal> LIT_INT LIT_FLOAT LIT_STRING

/* Tokens P3 (Control y Booleanos) */
%token IF THEN ELSE FI WHILE UNTIL FOR IN BREAK SWITCH CASE DEFAULT FSWITCH
%token AND OR NOT
%token EQ NEQ GT GE LT LE
%token <literal> LIT_BOOL

%token <ident> ID 

/* Tipos No Terminales */
%type <info> programa lista_sentencias sentencia
%type <info> declaracion asignacion
%type <info> expressio term potencia factor variable
%type <info> bool_expr M N 
%type <info> case_list case_item default_opt 

/* Precedencia ( NOT > AND > OR) */
%left OR
%left AND
%left NOT
%left EQ NEQ GT GE LT LE
%left PLUS MINUS
%left MULT DIV MOD
%right POW

%start programa

%%

programa : { cg_init(); } lista_sentencias { 
                cg_emit("HALT", NULL, NULL, NULL);
                cg_print_all(stdout); 
           }
         ;

lista_sentencias : /* vacio */ { $$.nextlist = NULL; $$.breaklist = NULL; }
                 | lista_sentencias M sentencia { 
                     /* BACKPATCHING: Rellenar saltos pendientes de sentencias anteriores */
                     backpatch($1.nextlist, $2.label_idx);
                     $$.nextlist = $3.nextlist;
                     /* PROPAGAR BREAKS: No backpatchear aquí, se pasan arriba */
                     $$.breaklist = merge($1.breaklist, $3.breaklist);
                 }
                 | lista_sentencias EOL { $$ = $1; }
                 ;

sentencia : declaracion EOL { $$.nextlist = NULL; $$.breaklist = NULL; }
          | asignacion EOL  { $$.nextlist = NULL; $$.breaklist = NULL; }
          | expressio EOL { 
               /* Imprimir expresión */
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
          /* --- ESTRUCTURAS DE CONTROL P3 --- */
          | IF bool_expr THEN M lista_sentencias FI {
              /* 1. Las sentencias se ejecutan si bool_expr es TRUE */
              backpatch($2.truelist, $4.label_idx);
              /* 2. Si es FALSE, salta al final (FI) */
              $$.nextlist = merge($2.falselist, $5.nextlist);
              $$.breaklist = $5.breaklist; /* Propagar breaks internos */
          }
          | IF bool_expr THEN M lista_sentencias N ELSE M lista_sentencias FI {
              /* 1. TRUE -> bloque THEN */
              backpatch($2.truelist, $4.label_idx);
              /* 2. FALSE -> bloque ELSE */
              backpatch($2.falselist, $8.label_idx);
              /* 3. Salida -> unión de salidas THEN (N) y ELSE */
              /* N genera un GOTO al final para saltarse el ELSE */
              ListNode *temp = merge($5.nextlist, $6.nextlist); /* nextlist de sentencia + GOTO N */
              $$.nextlist = merge(temp, $9.nextlist);
              $$.breaklist = merge($5.breaklist, $9.breaklist);
          }
          /* --- REPEAT --- */
          | REPEAT expressio DO 
          {
              /* $4: Acción de Inicialización */
              if ($2.type != T_INT) yyerror("REPEAT requereix una expressió entera");
              
              char *count = cg_new_temp();
              cg_emit(":=", $2.addr, NULL, count);
              
              /* Guardamos count en este nodo ($4) */
              $<info>$.addr = count;
          }
          M /* $5: Etiqueta inicio bucle */
          {
              /* $6: Acción de Condición */
              /* Recuperamos count de $4 */
              $<info>$.falselist = makelist(cg_next_quad());
              cg_emit("IF LEI", $<info>4.addr, "0", NULL);
          }
          lista_sentencias /* $7: Cuerpo */
          DONE /* $8 */
          {
              /* Decrement: count := count - 1 */
              /* Recuperamos count de $4 */
              char *count = $<info>4.addr;
              cg_emit("SUBI", count, "1", count);
              
              /* Salt incondicional a l'inici (M està a $5) */
              char str_label[16];
              sprintf(str_label, "%d", $5.label_idx);
              cg_emit("GOTO", NULL, NULL, str_label);
              
              /* Backpatch sortida (La llista false està a l'acció $6) */
              backpatch($<info>6.falselist, cg_next_quad());
              
              /* Propagar breaks (Estan a $7) */
              $$.nextlist = $7.breaklist;
              $$.breaklist = NULL;
          }
          | WHILE M bool_expr DO M lista_sentencias DONE {
              /* 1. Bucle: volver a evaluar condición (M1) */
              backpatch($6.nextlist, $2.label_idx);
              /* 2. TRUE -> ejecutar cuerpo (M2) */
              backpatch($3.truelist, $5.label_idx);
              
              char str_label[16];
              sprintf(str_label, "%d", $2.label_idx);
              cg_emit("GOTO", NULL, NULL, str_label);
              
              /* Salida del bucle: cuando es Falso O cuando hay un Break */
              $$.nextlist = merge($3.falselist, $6.breaklist); /* Aquí resolvemos los breaks del cuerpo */
              $$.breaklist = NULL; /* Los breaks ya se han consumido */
          }
          | DO M lista_sentencias UNTIL bool_expr {
              backpatch($3.nextlist, $2.label_idx);
              backpatch($5.falselist, $2.label_idx);
              $$.nextlist = merge($5.truelist, $3.breaklist); /* Breaks salen del bucle */
              $$.breaklist = NULL;
          }
          /* --- FOR --- */
          | FOR ID IN expressio RANGE expressio DO 
          {
              /* $8: Inicialización */
              if ($4.type != T_INT || $6.type != T_INT) yyerror("Rango FOR debe ser entero");
              cg_emit(":=", $4.addr, NULL, $2.lexema);
          } 
          M /* $9: Etiqueta Inicio */
          { 
              /* $10: Condición (Acción Incrustada) */
              /* Guardamos el límite en $<info>$ para usarlo después */
              
              /* Generamos salto de salida: IF i GTI limite GOTO ??? */
              $<info>$.falselist = makelist(cg_next_quad());
              cg_emit("IF GTI", $2.lexema, $6.addr, NULL); 
          } 
          lista_sentencias /* $11 */
          DONE 
          {
              /* $13: Final del bucle */
              
              /* 1. Incremento: i := i + 1 */
              cg_emit("ADDI", $2.lexema, "1", $2.lexema);
              
              /* 2. Salto incondicional al inicio (M -> $9) */
              char str_label[16];
              sprintf(str_label, "%d", $9.label_idx);
              cg_emit("GOTO", NULL, NULL, str_label);
              
              /* 3. Rellenar la salida (Backpatching) */
              /* Usar $<info>10 en lugar de $10 */
              backpatch($<info>10.falselist, cg_next_quad());
              
              /* 4. Propagar breaks */
              $$.nextlist = $11.breaklist; 
              $$.breaklist = NULL;
          }
          
          /* --- SWITCH --- */
          /* usar $8 en lugar de $7 porque opt_eol y la acción {} desplazan el índice */
          | SWITCH LPAREN expressio RPAREN opt_eol {
              switch_push($3.addr);
          } M_switch case_list FSWITCH {
              switch_pop();
              /* Backpatch de fallos (default implícito) al final */
              backpatch($8.falselist, cg_next_quad());
              
              /* La salida del switch es el flujo normal + los breaks */
              $$.nextlist = merge($8.nextlist, $8.breaklist); 
              $$.breaklist = NULL; 
          }
          | error EOL { yyerrok; $$.nextlist = NULL; $$.breaklist = NULL; }
          ;

/* --- REGLA AUXILIAR --- */
opt_eol : /* empty */ 
        | opt_eol EOL 
        ;

M_switch : { };

case_list : case_item case_list {
              $$.nextlist = merge($1.nextlist, $2.nextlist);
              $$.breaklist = merge($1.breaklist, $2.breaklist);
              backpatch($1.falselist, $2.label_idx);
              $$.falselist = $2.falselist;
              $$.label_idx = $1.label_idx; 
          }
          | default_opt { $$ = $1; }
          ;

case_item : CASE expressio COLON 
            { 
               /* ACCIÓN INCRUSTADA: Se ejecuta ANTES de lista_sentencias */
               /* 1. emitir el Test: IF control != caso GOTO siguiente */
               char *ctrl = switch_peek();
               
               /* guardar en $<info>$ los datos para recuperarlos luego */
               /* label_idx: Dónde empieza este caso (para que el anterior salte aquí) */
               $<info>$.label_idx = cg_next_quad();
               
               /* falselist: Lista de saltos si el caso NO coincide */
               $<info>$.falselist = makelist(cg_next_quad());
               cg_emit("IF NEQ", ctrl, $2.addr, NULL); 
            }
            lista_sentencias 
            {
               /* ACCIÓN FINAL */
               /* recuperar los datos de la acción incrustada ($4) */
               $$.label_idx = $<info>4.label_idx; 
               $$.falselist = $<info>4.falselist; 
               
               /* Propagar los datos del cuerpo ($5) */
               $$.nextlist = $5.nextlist;
               $$.breaklist = $5.breaklist;
            }
            ;

default_opt : DEFAULT COLON M lista_sentencias {
                $$.label_idx = $3.label_idx;
                $$.nextlist = $4.nextlist;
                $$.breaklist = $4.breaklist;
                $$.falselist = NULL;
            }
            | /* vacio */ { 
                $$.label_idx = cg_next_quad();
                $$.nextlist = NULL;
                $$.breaklist = NULL;
                $$.falselist = makelist(cg_next_quad()); 
            } 
            ;

M : { $$.label_idx = cg_next_quad(); } ;

N : { 
    /* Genera GOTO incompleto para saltar bloques (ej: fin del THEN) */
    $$.nextlist = makelist(cg_next_quad());
    cg_emit("GOTO", NULL, NULL, NULL);
} ;

/* Declaraciones */
declaracion : KW_INT ID   { install_var($2.lexema, T_INT, 0, 0); }
            | KW_FLOAT ID { install_var($2.lexema, T_FLOAT, 0, 0); }
            | KW_BOOL ID  { install_var($2.lexema, T_BOOL, 0, 0); }
            | KW_INT ID LBRACKET LIT_INT RBRACKET { install_var($2.lexema, T_INT, 1, atoi($4)); }
            ;

asignacion : variable ASSIGN expressio {
                if ($1.ctr_var == NULL) cg_emit(":=", $3.addr, NULL, $1.addr);
                else cg_emit("arr_set", $1.addr, $1.ctr_var, $3.addr);
             }
           ;

/* Booleanos */
bool_expr : bool_expr OR M bool_expr {
              /* Si $1 es TRUE, ya acabamos (es TRUE). Backpatching a $1.truelist se queda pendiente. */
              /* Si $1 es FALSE, saltamos a M ($3) para evaluar $4. */
              backpatch($1.falselist, $3.label_idx);
              $$.truelist = merge($1.truelist, $4.truelist);
              $$.falselist = $4.falselist;
          }
          | bool_expr AND M bool_expr {
              /* Si $1 es TRUE, saltamos a M ($3) para evaluar $4. */
              backpatch($1.truelist, $3.label_idx);
              /* Si $1 es FALSE, ya acabar */
              $$.truelist = $4.truelist;
              $$.falselist = merge($1.falselist, $4.falselist);
          }
          | NOT bool_expr {
              $$.truelist = $2.falselist;
              $$.falselist = $2.truelist;
          }
          | LPAREN bool_expr RPAREN { $$ = $2; }
          | expressio EQ expressio  { $$ = gen_relational_op("EQ", $1, $3); }
          | expressio NEQ expressio { $$ = gen_relational_op("NE", $1, $3); }
          | expressio GT expressio  { $$ = gen_relational_op("GT", $1, $3); }
          | expressio GE expressio  { $$ = gen_relational_op("GE", $1, $3); }
          | expressio LT expressio  { $$ = gen_relational_op("LT", $1, $3); }
          | expressio LE expressio  { $$ = gen_relational_op("LE", $1, $3); }
          | LIT_BOOL {
              if (strcmp($1, "1") == 0) { /* TRUE */
                  $$.truelist = makelist(cg_next_quad());
                  cg_emit("GOTO", NULL, NULL, NULL);
                  $$.falselist = NULL;
              } else { /* FALSE */
                  $$.falselist = makelist(cg_next_quad());
                  cg_emit("GOTO", NULL, NULL, NULL);
                  $$.truelist = NULL;
              }
          }
          ;

/* Aritmética */
expressio : term
          | expressio PLUS term  { $$ = gen_binary_op("ADD", $1, $3); }
          | expressio MINUS term { $$ = gen_binary_op("SUB", $1, $3); }
          ;

term : potencia
     | term MULT potencia { $$ = gen_binary_op("MUL", $1, $3); }
     | term DIV potencia  { $$ = gen_binary_op("DIV", $1, $3); }
     | term MOD potencia  { $$ = gen_binary_op("MOD", $1, $3); }
     ;

potencia : factor
         | factor POW potencia { $$ = gen_power($1, $3); }
         ;

factor : LIT_INT { $$.addr = strdup($1); $$.type = T_INT; $$.ctr_var=NULL; }
       | LIT_FLOAT { $$.addr = strdup($1); $$.type = T_FLOAT; $$.ctr_var=NULL; }
       | variable {
            if ($1.ctr_var == NULL) {
                $$.addr = $1.addr; $$.type = $1.type;
            } else {
                char *temp = cg_new_temp();
                cg_emit("arr_get", $1.addr, $1.ctr_var, temp);
                $$.addr = temp; $$.type = $1.type;
            }
       }
       | LPAREN expressio RPAREN { $$ = $2; }
       ;

variable : ID {
             $$.addr = strdup($1.lexema);
             $$.type = get_var_type($1.lexema);
             $$.ctr_var = NULL;
          }
          | ID LBRACKET expressio RBRACKET {
             char *offset_rel = cg_new_temp();
             cg_emit("MULI", $3.addr, "4", offset_rel);
             char *offset_final = cg_new_temp();
             cg_emit("ADDI", offset_rel, "25", offset_final);
             $$.addr = strdup($1.lexema);
             $$.type = get_var_type($1.lexema);
             $$.ctr_var = offset_final;
          }
          ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error sintáctico en línea %d: %s\n", yylineno, s);
}