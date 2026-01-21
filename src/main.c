#include <stdio.h>
#include <stdlib.h>

extern int yyparse();
extern FILE *yyin;

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <fichero_entrada>\n", argv[0]);
        return 1;
    }

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("Error al abrir el fichero");
        return 1;
    }

    /* el parser se encarga de llamar a cg_init() y cg_print_all() */
    if (yyparse() != 0) {
        fprintf(stderr, "Aborting due to syntax errors\n");
        return 1;
    }

    fclose(yyin);
    return 0;
}