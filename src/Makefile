# --- CONFIGURACIÓN ---
CC = gcc
CFLAGS = -Wall -g
LIBS = -lm

# Nombre del ejecutable
TARGET = calculadora

# Rutas relativas desde la carpeta 'src'
TEST_IN_DIR = ../test/in
TEST_OUT_DIR = ../test/out

# --- REGLAS PRINCIPALES ---

all: $(TARGET)

# Compilación del Ejecutable
$(TARGET): parser.tab.c scanner.c values.c symtab.c codegen.c main.c
	$(CC) $(CFLAGS) -o $(TARGET) values.c symtab.c codegen.c parser.tab.c scanner.c main.c $(LIBS)

# Generación del Analizador Sintáctico (Bison)
# Genera parser.tab.c y parser.tab.h
parser.tab.c parser.tab.h: parser.y
	bison -d -v parser.y

# Generación del Analizador Léxico (Flex)
# Depende de parser.tab.h porque necesita los tokens
scanner.c: scanner.l parser.tab.h
	flex -o scanner.c scanner.l

# --- REGLA DE TESTING ---
# 1. Crea la carpeta de salida si no existe.
# 2. Busca todos los .txt en ../test/in
# 3. Ejecuta la calculadora pasando el archivo como argumento.
# 4. Redirige la salida (stdout y stderr) a ../test/out/nombre.out
test: $(TARGET)
	@echo "--- INICIANDO BATERÍA DE TESTS ---"
	@mkdir -p $(TEST_OUT_DIR)
	@for filepath in $(TEST_IN_DIR)/*.txt; do \
		filename=$$(basename $$filepath); \
		echo "Procesando: $$filename ..."; \
		./$(TARGET) $$filepath > $(TEST_OUT_DIR)/$$filename.out 2>&1; \
	done
	@echo "--- FIN DE TESTS. Resultados en $(TEST_OUT_DIR) ---"

# --- LIMPIEZA ---
clean:
	rm -f $(TARGET) scanner.c parser.tab.c parser.tab.h parser.output
	rm -f $(TEST_OUT_DIR)/*.out

.PHONY: all clean test