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

/* --- HELPERS ARITMÉTICOS (P2) --- */
C3A_Info gen_binary_op(char *op_base, C3A_Info a, C3A_Info b) {
    C3A_Info res;
    res.type = T_ERROR;
    res.addr = NULL;
    res.ctr_var = NULL;
    /* Listas nulas para aritméticas */
    res.truelist = NULL;
    res.falselist = NULL;
    res.nextlist = NULL;

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
    C3A_Info res;
    res.type = T_ERROR;
    res.addr = NULL;
    if (a.type == T_ERROR) return res;

    res.type = a.type;
    res.addr = cg_new_temp();
    char *opcode = (a.type == T_INT) ? "CHSI" : "CHSF";
    cg_emit(opcode, a.addr, NULL, res.addr);
    return res;
}

/* --- HELPERS BOOLEANOS (P3) --- */
/* Genera saltos para comparaciones: IF x REL y GOTO _ */
C3A_Info gen_relational_op(char *rel_op, C3A_Info a, C3A_Info b) {
    C3A_Info res;
    res.type = T_BOOL;
    res.addr = NULL; /* Los booleanos no tienen valor, son flujo de control */
    
    /* Conversiones de tipo para comparar */
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
    sprintf(op_full, "IF %s%c", rel_op, suffix); /* Ej: IF LTI o IF LTF */
    
    cg_emit(op_full, addr_a, addr_b, NULL); /* res es NULL por ahora */

    /* Generar: GOTO (hueco falselist) */
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

/* Tokens P2 */
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
%type <info> bool_expr M N /* Marcadores para Backpatching */

/* Precedencia (P3: NOT > AND > OR) */
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

lista_sentencias : /* vacio */ { $$.nextlist = NULL; }
                 | lista_sentencias M sentencia { 
                     /* BACKPATCHING: Rellenar saltos pendientes de sentencias anteriores */
                     backpatch($1.nextlist, $2.label_idx);
                     $$.nextlist = $3.nextlist;
                 }
                 | lista_sentencias EOL { $$ = $1; }
                 ;

sentencia : declaracion EOL { $$.nextlist = NULL; }
          | asignacion EOL  { $$.nextlist = NULL; }
          | expressio EOL { 
               /* Imprimir expresión */
               cg_emit("PARAM", $1.addr, NULL, NULL);
               if ($1.type == T_FLOAT) cg_emit("CALL", "PUTF", "1", NULL);
               else cg_emit("CALL", "PUTI", "1", NULL);
               $$.nextlist = NULL;
            }
          /* --- ESTRUCTURAS DE CONTROL P3 --- */
          | IF bool_expr THEN M lista_sentencias FI {
              /* 1. Las sentencias se ejecutan si bool_expr es TRUE */
              backpatch($2.truelist, $4.label_idx);
              /* 2. Si es FALSE, salta al final (FI) */
              $$.nextlist = merge($2.falselist, $5.nextlist);
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
          }
          | WHILE M bool_expr DO M lista_sentencias DONE {
              /* 1. Bucle: volver a evaluar condición (M1) */
              backpatch($6.nextlist, $2.label_idx);
              /* 2. TRUE -> ejecutar cuerpo (M2) */
              backpatch($3.truelist, $5.label_idx);
              /* 3. FALSE -> salir del bucle */
              $$.nextlist = $3.falselist;
              /* 4. Emitir GOTO al inicio incondicional */
              char str_label[16];
              sprintf(str_label, "%d", $2.label_idx);
              cg_emit("GOTO", NULL, NULL, str_label);
          }
          | error EOL { yyerrok; $$.nextlist = NULL; }
          ;

/* --- MARCADORES PARA BACKPATCHING --- */
M : { $$.label_idx = cg_next_quad(); } ;

N : { 
    /* Genera GOTO incompleto para saltar bloques (ej: fin del THEN) */
    $$.nextlist = makelist(cg_next_quad());
    cg_emit("GOTO", NULL, NULL, NULL);
} ;

/* --- DECLARACIONES Y ASIGNACIONES (Igual que P2) --- */
declaracion : KW_INT ID   { install_var($2.lexema, T_INT, 0, 0); }
            | KW_FLOAT ID { install_var($2.lexema, T_FLOAT, 0, 0); }
            | KW_BOOL ID  { install_var($2.lexema, T_BOOL, 0, 0); }
            | KW_INT ID LBRACKET LIT_INT RBRACKET { install_var($2.lexema, T_INT, 1, atoi($4)); }
            /* ... más declaraciones ... */
            ;

asignacion : variable ASSIGN expressio {
                /* Asignación aritmética */
                if ($3.type == T_BOOL) yyerror("Error semántico: Asignación booleana no soportada en var numérica.");
                
                if ($1.ctr_var == NULL) cg_emit(":=", $3.addr, NULL, $1.addr);
                else cg_emit("arr_set", $1.addr, $1.ctr_var, $3.addr);
             }
           | variable ASSIGN bool_expr {
               /* Asignación booleana (Complejo: requiere materializar el flujo en 1/0) */
               /* PENDIENTE: Para P3 básica, asumimos variables numéricas mayormente */
               /* Si piden variables booleanas reales:
                  M_TRUE: x := 1, GOTO FIN
                  M_FALSE: x := 0
                  FIN: ...
               */
               yyerror("Asignación de expresiones booleanas complejas no implementada (Feature Extra).");
           }
           ;

/* --- EXPRESIONES BOOLEANAS (Cortocircuito) --- */
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
              /* Si $1 es FALSE, ya acabamos. */
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

/* --- EXPRESIONES ARITMÉTICAS (Jerarquía P2) --- */
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
         /* | factor POW potencia ... (Implementar si se necesita, bucle manual P2) */
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
          /* ... lógica de arrays P2 ... */
          ;

%%

void yyerror(const char *s) {
    fprintf(stderr, "Error sintáctico en línea %d: %s\n", yylineno, s);
}