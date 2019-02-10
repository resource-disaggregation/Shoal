#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <assert.h>

#include "min_priority_queue.h"

#define NULL_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d Null pointer exception\n", __FILE__, line_num); \
        exit(0);}

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

struct min_priority_queue {
    void** array;
    int32_t size;
    int32_t max_size;
    compare_func_t compare;
    update_index_func_t update_index;
};

static inline int32_t left_child_index(int32_t index)
{
    return ((2 * index) + 1);
}

static inline int32_t right_child_index(int32_t index)
{
    return ((2 * index) + 2);
}

static inline int32_t parent_index(int32_t index)
{
    if (index == 0) return 0;
    else return (floor((index - 1)/2.0));
}

//propagates heap condition downwards
static void min_heapify(min_priority_queue_t self, int32_t index)
{
    int32_t left = left_child_index(index);
    int32_t right = right_child_index(index);

    int32_t smallest = index;

    if ((left <= self->size)
         && (self->compare(self->array[left], self->array[index]) == -1)) {
        smallest = left;
    }

    if ((right <= self->size)
         && (self->compare(self->array[right], self->array[smallest]) == -1)) {
        smallest = right;
    }

    if (smallest != index) {
        void* temp = self->array[index];
        self->array[index] = self->array[smallest];
        self->array[smallest] = temp;
        self->update_index(self->array[index], index);
        self->update_index(self->array[smallest], smallest);
        min_heapify(self, smallest);
    }
}

min_priority_queue_t create_min_priority_queue
    (int32_t max_size, compare_func_t f, update_index_func_t g)
{
    min_priority_queue_t self
        = (min_priority_queue_t) malloc(sizeof(struct min_priority_queue));
    MALLOC_TEST(self, __LINE__);
    self->array = (void**) malloc(max_size * sizeof(void*));
    MALLOC_TEST(self->array, __LINE__);
    self->size = 0;
    self->max_size = max_size;
    self->compare = f;
    self->update_index = g;
    return self;
}

//propagates heap condition upwards
void update_priority_at_index(min_priority_queue_t self, int32_t index)
{
    int32_t i = index;
    int32_t parent = parent_index(i);
    while ((i > 0)
            && (self->compare(self->array[parent], self->array[i]) == 1)) {
        void* temp = self->array[parent];
        self->array[parent] = self->array[i];
        self->array[i] = temp;
        self->update_index(self->array[i], i);
        self->update_index(self->array[parent], parent);
        i = parent_index(i);
        parent = parent_index(i);
    }
}

void min_priority_queue_insert(min_priority_queue_t self, void* element)
{
    NULL_TEST(self, __LINE__);
    NULL_TEST(element, __LINE__);

    if (self->size < self->max_size) {
        self->array[self->size] = element;
        self->update_index(self->array[self->size], self->size);
        ++(self->size);
        update_priority_at_index(self, self->size - 1);
    }
}

void* min_priority_queue_extract(min_priority_queue_t self)
{
    NULL_TEST(self, __LINE__);

    if (self->size > 0) {
        void* min = self->array[0];
        self->array[0] = self->array[self->size - 1];
        self->update_index(self->array[0], 0);
        --self->size;
        min_heapify(self, 0);
        return min;
    } else {
        return NULL;
    }
}

void* min_priority_queue_peek(min_priority_queue_t self)
{
    NULL_TEST(self, __LINE__);

    if (self->size > 0) {
        return self->array[0];
    } else {
        return NULL;
    }
}

void min_priority_queue_remove(min_priority_queue_t self, int32_t index)
{
    NULL_TEST(self, __LINE__);
    assert(index >= 0 && index < self->size);
    //assumes that the caller has set the priority of array[index] to MIN
    update_priority_at_index(self, index);
    free(min_priority_queue_extract(self));
}

void* min_priority_queue_get(min_priority_queue_t self, int32_t index)
{
    NULL_TEST(self, __LINE__);
    assert(index >= 0 && index < self->size);
    return self->array[index];
}

int32_t min_priority_queue_size(min_priority_queue_t self)
{
    NULL_TEST(self, __LINE__);
    return self->size;
}

void free_min_priority_queue(min_priority_queue_t self)
{
    if (self != NULL) {
        free(self->array);
        free(self);
    }
}
