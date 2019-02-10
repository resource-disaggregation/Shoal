#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>

#include "bounded_buffer.h"

#define NULL_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d Null pointer exception\n", __FILE__, line_num); \
        exit(0);}

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

struct bounded_buffer {
    void** buffer;
    int32_t size;
    int64_t head;
    int64_t tail;
};

bounded_buffer_t create_bounded_buffer(int32_t size)
{
    bounded_buffer_t self = NULL;
    if (size > 0) {
        self = (bounded_buffer_t) malloc(sizeof(struct bounded_buffer));
        MALLOC_TEST(self, __LINE__);
        self->buffer = (void**) malloc(size * sizeof(void*));
        MALLOC_TEST(self->buffer, __LINE__);
        self->size = size;
        self->head = 0;
        self->tail = 0;
    }
    return self;
}

void bounded_buffer_put(bounded_buffer_t self, void* element)
{
    NULL_TEST(self, __LINE__);

    if (self->head != (self->tail + self->size)) {
        self->buffer[(self->head % self->size)] = element;
        ++(self->head);
    }
}

void* bounded_buffer_get(bounded_buffer_t self)
{
    NULL_TEST(self, __LINE__);

    if (self->head != self->tail) {
        void* element = self->buffer[(self->tail % self->size)];
        ++(self->tail);
        return element;
    } else {
        return NULL;
    }
}

void* bounded_buffer_peek(bounded_buffer_t self, int32_t index)
{
    NULL_TEST(self, __LINE__);

    assert(index >= 0 && index < (self->head - self->tail));

    int32_t start_index = self->tail % self->size;
    int32_t idx = (start_index + index) % self->size;

    return self->buffer[idx];
}

int32_t bounded_buffer_num_of_elements(bounded_buffer_t self)
{
    NULL_TEST(self, __LINE__);
    return (self->head - self->tail);
}

void bounded_buffer_clear(bounded_buffer_t self)
{
    self->head = 0;
    self->tail = 0;
}

void free_bounded_buffer(bounded_buffer_t self)
{
    if (self != NULL) {
        free(self->buffer);
        free(self);
    }
}
