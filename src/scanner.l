%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "values.h"
#include "codegen.h"
#include "parser.tab.h"

void setup_id() {
    yylval.ident.lexema = strdup(yytext);
    yylval.ident.line = yylineno;
}
%}

%option yylineno
%option noyywrap
%option nounput
%option noinput

digit       [0-9]
enter       {digit}+
real        {digit}+\.{digit}*([eE][+-]?{digit}+)?|{digit}+[eE][+-]?{digit}+|\.{digit}+([eE][+-]?{digit}+)?
identif     [a-zA-Z]([a-zA-Z0-9_])*

%%

    /* --- COMENTARIOS --- */
"//"[^\n]* { /* Ignorar texto comentario, pero NO el \n */ }
"#"[^\n]* { /* Ignorar texto comentario, pero NO el \n */ }
"/*"([^*]|(\*+[^*/]))*\*+\/ { /* Comentario bloque normal */ }

    /* --- DELIMITADORES --- */
\n          { return EOL; }
[ \t\r]+    { /* Ignorar espacios y tabs */ }
";"         { return SEMICOLON; }
":"         { return COLON; }    /* NECESARIO PARA CASE  */
","         { return COMMA; }
".."        { return RANGE; }    /* NECESARIO PARA FOR  */
"."         { return DOT; }
"["         { return LBRACKET; }
"]"         { return RBRACKET; }

    /* --- PALABRAS RESERVADAS TIPOS --- */
"int"       { return KW_INT; }
"float"     { return KW_FLOAT; }
"string"    { return KW_STRING; }
"bool"      { return KW_BOOL; }
"struct"    { return STRUCT; }
"true"      { yylval.literal = strdup("1"); return LIT_BOOL; }
"false"     { yylval.literal = strdup("0"); return LIT_BOOL; }

    /* --- ESTRUCTURAS DE CONTROL --- */
"repeat"    { return REPEAT; }
"do"        { return DO; }
"done"      { return DONE; }

"if"        { return IF; }       /* [cite: 592] */
"then"      { return THEN; }     /* [cite: 592] */
"else"      { return ELSE; }     /* [cite: 600] */
"fi"        { return FI; }       /* [cite: 594] */

"while"     { return WHILE; }    /* [cite: 626] */
"until"     { return UNTIL; }    /* [cite: 632] */
"for"       { return FOR; }      /* [cite: 634] */
"in"        { return IN; }       /* [cite: 634] */
"break"     { return BREAK; }    /* [cite: 612] */

"switch"    { return SWITCH; }   /* [cite: 604] */
"case"      { return CASE; }     /*  */
"default"   { return DEFAULT; }  /* [cite: 608] */
"fswitch"   { return FSWITCH; }  /* [cite: 611] */

    /* --- OPERADORES --- */
":="        { return ASSIGN; }
"+"         { return PLUS; }
"-"         { return MINUS; }
"*"         { return MULT; }
"/"         { return DIV; }
"%"         { return MOD; }
"**"        { return POW; }

"and"       { return AND; }      /* [cite: 576] */
"or"        { return OR; }       /* [cite: 576] */
"not"       { return NOT; }      /* [cite: 576] */
">="        { return GE; }
"<="        { return LE; }
"<>"        { return NEQ; }      /* [cite: 576] */
">"         { return GT; }
"<"         { return LT; }
"="         { return EQ; }       /* [cite: 576] */

"("         { return LPAREN; }
")"         { return RPAREN; }
"{"         { return LBRACE; }
"}"         { return RBRACE; }

    /* --- FUNCIONES --- */
"sin"       { return KW_SIN; }
"cos"       { return KW_COS; }
"tan"       { return KW_TAN; }
"LEN"       { return KW_LEN; }
"len"       { return KW_LEN; }
"SUBSTR"    { return KW_SUBSTR; }
"substr"    { return KW_SUBSTR; }

    /* --- LITERALES --- */
{enter}     { yylval.literal = strdup(yytext); return LIT_INT; }
{real}      { yylval.literal = strdup(yytext); return LIT_FLOAT; }

\"[^\"\n]*\" { 
              yylval.ident.lexema = strdup(yytext + 1);
              yylval.ident.lexema[yyleng - 2] = '\0';
              yylval.ident.line = yylineno; 
              return LIT_STRING; 
            }

{identif}   { setup_id(); return ID; }

.           { printf("Lexical Error: %s\n", yytext); }

%%