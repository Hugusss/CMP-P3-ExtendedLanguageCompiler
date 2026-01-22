#include <stdio.h>
#include <stdlib.h>
#include "codegen.h"
#include "symtab.h"

extern FILE *yyin;
extern int yyparse();

FILE *flog = NULL; /* Global log file */

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <fichero_entrada>\n", argv[0]);
        return 1;
    }

    yyin = fopen(argv[1], "r");
    if (!yyin) {
        perror("Error abriendo fichero");
        return 1;
    }

    cg_init();
    
    flog = fopen("audit.log", "a");
    
    /* separador visual para distinguir ejecuciones en el log */
    if (flog) {
        fprintf(flog, "\n========================================\n");
        fprintf(flog, "--- INICIO COMPILACIÓN: %s ---\n", argv[1]);
    }

    yyparse();

    if (flog) {
        fprintf(flog, "--- FIN COMPILACIÓN ---\n");
        fclose(flog);
    }

    cg_dump_code(stdout);
    fclose(yyin);
    return 0;
}