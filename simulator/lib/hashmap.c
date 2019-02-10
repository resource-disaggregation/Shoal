#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

#include "hashmap.h"

#define NULL_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d Null pointer exception\n", __FILE__, line_num); \
        exit(0);}

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

struct map_item {
    char* key;
    void* value;
};

typedef struct map_item* map_item_t;

struct hashmap {
    arraylist_t* map;
    uint64_t num_of_items;
    uint64_t num_of_buckets;
};

uint32_t jenkins_hash(char* key)
{
    uint32_t hash, i;
    uint32_t len = strlen(key);
    for(hash = i = 0; i < len; ++i) {
        hash += key[i];
        hash += (hash << 10);
        hash ^= (hash >> 6);
    }
    hash += (hash << 3);
    hash ^= (hash >> 11);
    hash += (hash << 15);
    return hash;
}

hashmap_t create_hashmap()
{
    hashmap_t self = (hashmap_t) malloc(sizeof(struct hashmap));
    MALLOC_TEST(self, __LINE__);
    self->map = (arraylist_t*) malloc(sizeof(arraylist_t));
    MALLOC_TEST(self->map, __LINE__);
    self->map[0] = NULL;
    self->num_of_items = 0;
    self->num_of_buckets = 1;
    return self;
}

static void hashmap_rehash(hashmap_t self)
{
    for (int64_t i = 0; i < self->num_of_buckets/2; ++i) {
        arraylist_t list = self->map[i];
        if (list == NULL) continue;
        for (int64_t j = 0; j < arraylist_size(list); ++j) {
            map_item_t item = (map_item_t)arraylist_get(list, j);
            uint32_t hash = jenkins_hash(item->key);
            int64_t index = hash % (self->num_of_buckets);
            if (index != i) {
                arraylist_remove(list, j);
                if (self->map[index] == NULL) self->map[index] = create_arraylist();
                arraylist_add(self->map[index], item);
            }
        }
    }
}

static int64_t get_index(arraylist_t list, char* key)
{
    assert(list != NULL && key != NULL);
    int64_t len = arraylist_size(list);
    for (int64_t index = 0; index < len; ++index) {
        map_item_t item = (map_item_t)arraylist_get(list, index);
        if (strcmp(key, item->key) == 0) return index;
    }
    return -1;
}

void hashmap_put(hashmap_t self, char* key, void* value)
{
    NULL_TEST(self, __LINE__);
    NULL_TEST(key, __LINE__);

    map_item_t item = (map_item_t) malloc(sizeof(struct map_item));
    MALLOC_TEST(item, __LINE__);
    *item = (struct map_item) {
        .key = key,
        .value = value
    };

    uint32_t hash = jenkins_hash(key);
    int64_t index = hash % (self->num_of_buckets);

    if (self->map[index] == NULL) self->map[index] = create_arraylist();
    arraylist_t list = self->map[index];
    int64_t i = get_index(list, key); //to check if key already exists
    if (i != -1) {
        arraylist_update(list, item, i);
    } else {
        arraylist_add(list, item);
        ++(self->num_of_items);
    }

    if ((self->num_of_items / self->num_of_buckets) >= 2) {
        self->map = (arraylist_t*)
            realloc(self->map, 2 * self->num_of_buckets * sizeof(void*));
        MALLOC_TEST(self->map, __LINE__);
        self->num_of_buckets *= 2;
        for (int64_t j = self->num_of_buckets/2; j < self->num_of_buckets; ++j) {
            self->map[j] = NULL;
        }

        hashmap_rehash(self);
    }
}

void* hashmap_get(hashmap_t self, char* key)
{
    NULL_TEST(self, __LINE__);
    NULL_TEST(key, __LINE__);

    uint32_t hash = jenkins_hash(key);
    int64_t index = hash % (self->num_of_buckets);

    arraylist_t list = self->map[index];
    if (list == NULL) return NULL;
    for (int64_t i = 0; i < arraylist_size(list); ++i) {
        map_item_t item = arraylist_get(self->map[index], i);
        if (strcmp(key, item->key) == 0) {
            return item->value;
        }
    }

    return NULL;
}

arraylist_t hashmap_keyset(hashmap_t self)
{
    arraylist_t keyset = create_arraylist();

    for (int64_t i = 0; i < self->num_of_buckets; ++i) {
        arraylist_t list = self->map[i];
        if (list != NULL) {
            int64_t len = arraylist_size(list);
            for (int64_t j = 0; j < len; ++j) {
                map_item_t item = (map_item_t)arraylist_get(list, j);
                arraylist_add(keyset, item->key);
            }
        }
    }

    return keyset;
}

void free_hashmap(hashmap_t self)
{
    if (self != NULL) {
        for (int64_t i = 0; i < self->num_of_buckets; ++i) {
            free_arraylist(self->map[i]);
        }
        free(self);
    }
}

void print_hashmap(hashmap_t self)
{
    for (int64_t i = 0; i < self->num_of_buckets; ++i) {
        printf("%ld -> ", i);
        arraylist_t list = self->map[i];
        if (list == NULL) {printf("NULL\n"); continue;}
        int64_t len = arraylist_size(list);
        for (int64_t j = 0; j < len; ++j) {
            map_item_t item = (map_item_t)arraylist_get(list, j);
            printf("(%d, %d) ", *((int*)item->key), *((int*)item->value));
        }
        printf("\n");
    }

}
