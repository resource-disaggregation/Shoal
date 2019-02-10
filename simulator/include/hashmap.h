#ifndef __HASHMAP_H__
#define __HASHMAP_H__

#include <stdint.h>
#include "arraylist.h"

typedef struct hashmap* hashmap_t;

hashmap_t create_hashmap();
void hashmap_put(hashmap_t, char*, void*);
void* hashmap_get(hashmap_t, char*);
arraylist_t hashmap_keyset(hashmap_t);
void free_hashmap(hashmap_t);
void print_hashmap(hashmap_t);

#endif
