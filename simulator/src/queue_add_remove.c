#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>

#include "queue_add_remove.h"
#include "node.h"
#include "flow.h"
#include "driver.h"

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

void add_flow_to_host_flow_queues(node_t node, int16_t flow_dst_index)
{
    for (int16_t i = 0; i < NUM_OF_NODES - 1; ++i) {
        int16_t mid = node->schedule_table[i];
        host_flow_queue_element_t x = (host_flow_queue_element_t)
                    malloc(sizeof(struct host_flow_queue_element));
        MALLOC_TEST(x, __LINE__);
        x->dst_index = flow_dst_index;

#ifdef debug
        if (node->last_throttle_value[mid][flow_dst_index] == -1) {
            printf("[%ld/%ld] node = %d  mid = %d  flow_dst_index = %d\n",
                    curr_timeslot, curr_epoch, node->node_index, mid,
                    flow_dst_index);
        }
#endif
        assert(node->last_throttle_value[mid][flow_dst_index] != -1);

        //set the throttle value
        x->throttle_value = node->last_throttle_value[mid][flow_dst_index];
        node->last_throttle_value[mid][flow_dst_index] = -1;

        //set the start time
        x->start_time = curr_timeslot;

        if (node->host_pkt_allocated[mid][flow_dst_index] == 1) {
#ifdef debug
            if (x->throttle_value != INT64_MAX) {
                printf("[%ld/%ld] node = %d  mid = %d  flow_dst_index = %d  %ld\n",
                    curr_timeslot, curr_epoch, node->node_index, mid,
                    flow_dst_index, x->throttle_value);
            }
#endif
            assert(x->throttle_value == INT64_MAX);
        }

        arraylist_add(node->host_flow_queue[mid], x);
    }
}

void remove_flow_from_host_flow_queues(node_t node, int16_t flow_dst_index)
{
    for (int16_t i = 0; i < NUM_OF_NODES-1; ++i) {
        int16_t mid = node->schedule_table[i];

        int8_t found = 0;
        int32_t size = arraylist_size(node->host_flow_queue[mid]);
        for (int32_t j = 0; j < size; ++j) {
            host_flow_queue_element_t x
                = arraylist_get(node->host_flow_queue[mid], j);
            if (x->dst_index == flow_dst_index) {
                found = 1;

                assert(node->last_throttle_value[mid][flow_dst_index] == -1
                        && x->throttle_value != -1);

                node->last_throttle_value[mid][flow_dst_index] = x->throttle_value;

#ifdef debug
                if (node->node_index == 95 && flow_dst_index == 5) {
                    printf("temp_pri[%d][%d] = %ld -- %ld\n", mid, flow_dst_index,
                            node->last_throttle_value[mid][flow_dst_index],
                            x->throttle_value);
                }
#endif

                arraylist_remove(node->host_flow_queue[mid], j);
                break;
            }
        }
        assert(found == 1);
    }
}

