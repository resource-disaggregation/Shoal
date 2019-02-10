#ifndef __MIN_PRIORITY_QUEUE__
#define __MIN_PRIORITY_QUEUE__

#include <stdint.h>

typedef struct min_priority_queue* min_priority_queue_t;
typedef int8_t (*compare_func_t)(void*, void*);
typedef void (*update_index_func_t)(void*, int32_t);

min_priority_queue_t create_min_priority_queue(int32_t, compare_func_t, update_index_func_t);
void min_priority_queue_insert(min_priority_queue_t, void*);
void* min_priority_queue_extract(min_priority_queue_t);
void* min_priority_queue_peek(min_priority_queue_t);
void min_priority_queue_remove(min_priority_queue_t, int32_t);
void update_priority_at_index(min_priority_queue_t, int32_t);
void* min_priority_queue_get(min_priority_queue_t, int32_t);
int32_t min_priority_queue_size(min_priority_queue_t);
void free_min_priority_queue(min_priority_queue_t);

#endif
