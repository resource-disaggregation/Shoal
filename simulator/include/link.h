#ifndef __LINK_H__
#define __LINK_H__

#include <stdint.h>

typedef struct link* link_t;

link_t create_link(int16_t, int16_t, int32_t);
void link_enqueue(link_t, void*);
void* link_dequeue(link_t);
void free_link(link_t);

#endif
