#include <stdlib.h>
#include "values.h"

value_info* create_value(C3AType t, int is_array, int length) {
    value_info *v = (value_info*)malloc(sizeof(value_info));
    v->type = t;
    v->is_array = is_array;
    v->length = length;
    return v;
}