# Práctica 3: Compilador con Generación de Código Intermedio (C3A)

## 1. Introducción y Objetivos
Este proyecto implementa un compilador completo capaz de traducir un lenguaje de alto nivel (con soporte para tipos estáticos, estructuras de control avanzadas y arrays) a **Codi de Tres Adreces (C3A)** .

El objetivo principal ha sido el desarrollo del **Backend** del compilador, implementando técnicas avanzadas como **Backpatching** para el control de flujo y **Optimización de Bucles (Loop Unrolling)** mediante manipulación directa del buffer de instrucciones.

## 2. Compilación y Ejecución
El proyecto incluye un `Makefile` robusto que gestiona la limpieza de logs y la compilación incremental.

### Requisitos

* GCC, Flex y Bison.

### Instrucciones
*Dentro de la carpeta `/src`:*
1. **Compilar el proyecto:**
    ```bash
    make
    ```

2. **Ejecutar los tests:**
    ```bash
    make test
    ```
    *Esto ejecutará todos los scripts en `test/in/`, generará los outputs en `test/out/` y registrará la trazabilidad en `audit.log`.*

3. **Ejecución manual:**
    ```bash
    ./calculadora test/in/mi_test.txt
    ``` 

4. **Limpieza:**
    ```bash
    make clean
    ```
    *Elimina ejecutables, código intermedio generado y reinicia el fichero de auditoría.*

## 3. Arquitectura del Sistema
El compilador se ha diseñado siguiendo una arquitectura de una sola pasada (One-Pass Compiler) modificada con un **Buffer de Emisión**, lo que permite manipulaciones *a posteriori* del código generado.

### Módulos Principales:
* **`parser.y` (Sintaxis):** Define la gramática estratificada (sin conflictos Shift/Reduce y sin operadores `%left/%right`) y dirige la traducción guiada por la sintaxis.
* **`scanner.l` (Léxico):** Tokenizador que soporta identificadores, literales (enteros, flotantes, booleanos, strings) y palabras reservadas.

* **`codegen.c/h` (Backend):** Gestiona un **Buffer de Instrucciones** (`code_memory[]`) en RAM en lugar de imprimir directamente a disco.
    * Implementa la lógica de duplicación de código para optimizaciones.
    * Gestiona la emisión de cuádruplas (Quadruples).
* **`symtab.c/h` (Semántica):** Tabla de símbolos para gestión de tipos y direcciones de memoria.
* **`values.c/h`:** Estructuras auxiliares para el paso de atributos sintetizados ($$) en Bison.

## 4. Decisiones de Diseño y Detalles de Implementación

### 4.1. Gramática Estratificada (Precedencia)
Siguiendo estrictamente los requisitos, **no se han utilizado los operadores de precedencia de Bison** (`%left`, `%right`). En su lugar, se ha implementado una gramática en cascada para definir la jerarquía de operaciones:

1. `expression` (OR) - *Menor precedencia*
2. `bool_term` (AND)
3. `bool_factor` (NOT, Relacionales)
4. `arith_expr` (+, -)
5. `term` (*, /, MOD)
6. `factor` (POW, Menos Unario)
7. `atom` (Paréntesis, Literales) - *Mayor precedencia*

### 4.2. Backpatching (Relleno de Saltos)
El control de flujo (`IF`, `WHILE`, `BOOLEANOS`) se resuelve mediante **Backpatching**.

* **Funcionamiento:** No se generan etiquetas explícitas al momento de emitir saltos (`GOTO`, `IF...`). En su lugar, se crean listas de "agujeros" pendientes de rellenar:
    * `truelist`: Saltos a ejecutar si la condición es cierta.
    * `falselist`: Saltos a ejecutar si la condición es falsa.
    * `nextlist`: Saltos incondicionales al final de un bloque.
    * `breaklist`: Saltos generados por la instrucción `break`.

* **Resolución:** Cuando el parser reduce una estructura (ej. cierra un `IF` o un `WHILE`), se conoce la dirección de la siguiente instrucción (`cg_next_quad()`) y se llama a `backpatch()` para rellenar las direcciones pendientes en las listas acumuladas.

### 4.3. Loop Unrolling (Optimización)
Para cumplir con el loop unrolling, se rediseñó `codegen.c` para no escribir en el fichero de salida inmediatamente.

* **Implementación:**
    1. El código se guarda en un array en memoria (`code_memory`).
    2. Cuando se detecta un bucle `REPEAT` con un literal pequeño (ej. `repeat 3`), se activa el flag `is_unrollable`.
    3. Se utiliza la función `cg_clone_code(start, end, times)`.

* **Recálculo de Saltos:** La función de clonado es inteligente. Si detecta una instrucción de salto (`GOTO` o `IF`) cuyo destino está **dentro** del bloque que se está copiando, **recalcula la etiqueta destino** sumándole el desplazamiento (offset) actual. Esto garantiza que la lógica interna del bucle copiado se mantenga íntegra y no salte al bloque original.

## 5. Implementación de Estructuras Específicas
A continuación, se detallan aspectos técnicos de diseño críticos.

### 5.1. Construcción del `SWITCH / CASE`
El `SWITCH` se ha implementado utilizando una **Pila de Control (`switch_stack`)** para permitir el anidamiento (switches dentro de switches).

* **Funcionamiento**:
    1. Al entrar en `SWITCH(expr)`, el compilador evalúa `expr` y empuja la dirección de la variable temporal resultante a la pila `switch_stack`.
    2. Cada `CASE val:` genera una comprobación explícita mediante **Acciones Incrustadas** en Bison *antes* de procesar el cuerpo del case:
    ```text
    IF NEQ switch_expr val GOTO next_case_label
    ```

    3. Al salir del `SWITCH`, se hace `pop` de la pila, restaurando el contexto para un switch exterior si existiera.

* **Operaciones anidadas**: Gracias a la pila, cada `CASE` siempre compara contra el valor de control del `SWITCH` más reciente, permitiendo anidar `SWITCH`, `WHILE` o `IF` libremente dentro de los casos.

### 5.2. Comportamiento `BREAK`
* El compilador implementa la lógica de "fall-through" estándar. Si no hay instrucción `BREAK` (que genera un `GOTO` a la lista `breaklist`), el flujo de ejecución continúa secuencialmente hacia la siguiente instrucción.
* En esta implementación, la siguiente instrucción suele ser la **comprobación condicional** del siguiente `CASE`. Por tanto, si no hubiera _break_, no ejecuta el código del siguiente caso automáticamente, sino que **evalúa la condición del siguiente caso**.

### 5.3. Sistema de Auditoría
Se ha implementado un sistema de **Logging** (`audit.log`) que registra eventos internos durante la compilación:

* Declaración de variables.
* Detección de optimizaciones (Unrolling).
* Errores sintácticos y semánticos.
* El log funciona en modo *append* dentro de una ejecución, pero se limpia automáticamente al iniciar una nueva batería de pruebas (`make test`), facilitando la depuración.