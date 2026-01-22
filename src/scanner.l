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
real        {digit}+\.{digit}+([eE][+-]?{digit}+)?|{digit}+[eE][+-]?{digit}+|\.{digit}+([eE][+-]?{digit}+)?
identif     [a-zA-Z]([a-zA-Z0-9_])*

%%

    /* --- COMENTARIOS --- */
"//"[^\n]* { }
"#"[^\n]* { }
"/*"([^*]|(\*+[^*/]))*\*+\/ { }

    /* --- DELIMITADORES --- */
\n          { return EOL; }
[ \t\r]+    { }
";"         { return SEMICOLON; }
":"         { return COLON; }
","         { return COMMA; }
".."        { return RANGE; }
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

"if"        { return IF; }
"then"      { return THEN; }
"else"      { return ELSE; }
"fi"        { return FI; }

"while"     { return WHILE; }
"until"     { return UNTIL; }
"for"       { return FOR; }
"in"        { return IN; }
"break"     { return BREAK; }

"switch"    { return SWITCH; }
"case"      { return CASE; }
"default"   { return DEFAULT; }
"fswitch"   { return FSWITCH; }

    /* --- OPERADORES --- */
":="        { return ASSIGN; }
"+"         { return PLUS; }
"-"         { return MINUS; }
"*"         { return MULT; }
"/"         { return DIV; }
"%"         { return MOD; }
"**"        { return POW; }

"and"       { return AND; }
"or"        { return OR; }
"not"       { return NOT; }
">="        { return GE; }
"<="        { return LE; }
"<>"        { return NEQ; }
">"         { return GT; }
"<"         { return LT; }
"="         { return EQ; }

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