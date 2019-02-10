#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "link.h"
#include "bounded_buffer.h"

#define NULL_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d Null pointer exception\n", __FILE__, line_num); \
        exit(0);}

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

struct link {
    int16_t src_node;
    int16_t dst_node;
    bounded_buffer_t fifo;
};

link_t create_link(int16_t src_node, int16_t dst_node, int32_t capacity)
{
    link_t self = (link_t) malloc(sizeof(struct link));
    MALLOC_TEST(self, __LINE__);
    self->src_node = src_node;
    self->dst_node = dst_node;
    self->fifo = create_bounded_buffer(capacity);
    return self;
}

void link_enqueue(link_t self, void* element)
{
    NULL_TEST(self, __LINE__);
    bounded_buffer_put(self->fifo, element);
}

void* link_dequeue(link_t self)
{
    NULL_TEST(self, __LINE__);
    return bounded_buffer_get(self->fifo);
}

void free_link(link_t self)
{
    if (self != NULL) {
        free_bounded_buffer(self->fifo);
        free(self);
    }
}
