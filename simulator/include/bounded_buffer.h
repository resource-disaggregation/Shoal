#ifndef __BOUNDED_BUFFER_H__
#define __BOUNDED_BUFFER_H__

#include<stdint.h>

typedef struct bounded_buffer* bounded_buffer_t;

bounded_buffer_t create_bounded_buffer(int32_t);
void bounded_buffer_put(bounded_buffer_t, void*);
void* bounded_buffer_get(bounded_buffer_t);
void* bounded_buffer_peek(bounded_buffer_t, int32_t);
int32_t bounded_buffer_num_of_elements(bounded_buffer_t);
void bounded_buffer_clear(bounded_buffer_t);
void free_bounded_buffer(bounded_buffer_t);

#endif
