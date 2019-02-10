#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

#include "flow.h"

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

flow_send_t create_host_flow(int16_t host_index, int16_t dst_index)
{
    flow_send_t self = (flow_send_t) malloc(sizeof(struct flow_params_sender));
    MALLOC_TEST(self, __LINE__);
    *self = (struct flow_params_sender) {
        .active = 0,
        .num_flow_in_progress = 0,
        .flow_size = 0,
        .pkt_transmitted = 0,
        .pkt_received = 0,
        .src = host_index,
        .dst = dst_index,
#ifdef SHORTEST_FLOW_FIRST
        .curr_min_flow_size = 0,
#endif
        .curr_flow_id = 0
    };

    for (int16_t i = 0; i < MAX_FLOW_ID; ++i) {
        self->flow_stat_logger_sender_list[i]
            = (struct flow_stat_logger_sender) {
                .flow_id = -1,
                .flow_stat_logger_sender_app_list = create_arraylist()
            };
    }

    return self;
}

flow_recv_t create_dst_flow(int16_t host_index, int16_t dst_index)
{
    flow_recv_t self = (flow_recv_t) malloc(sizeof(struct flow_params_receiver));
    MALLOC_TEST(self, __LINE__);
    *self = (struct flow_params_receiver) {
        .src = host_index,
        .dst = dst_index,
        .flow_stat_logger_receiver_list = create_arraylist()
    };

    return self;
}

void free_host_flow(flow_send_t self)
{
    if (self != NULL) {
        for (int16_t i = 0; i < MAX_FLOW_ID; ++i) {
            free_arraylist(self->flow_stat_logger_sender_list[i]
                    .flow_stat_logger_sender_app_list);
        }
        free(self);
    }
}

void free_dst_flow(flow_recv_t self)
{
    if (self != NULL) {
        free_arraylist(self->flow_stat_logger_receiver_list);
        free(self);
    }
}
