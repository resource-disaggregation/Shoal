#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>

#include "node.h"

#define NULL_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d Null pointer exception\n", __FILE__, line_num); \
        exit(0);}

#define MALLOC_TEST(ptr, line_num) \
    if (ptr == NULL) \
        {printf("error: %s:%d malloc() failed\n", __FILE__, line_num); \
        exit(0);}

node_t create_node(int16_t node_index, int16_t* schedule_table)
{
    node_t self = (node_t) malloc(sizeof(struct node));
    MALLOC_TEST(self, __LINE__);

    self->node_index = node_index;
    self->schedule_table = schedule_table;

    for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
        self->fwd_buffer[i] = create_bounded_buffer(FWD_BUFFER_LEN);
        self->host_flow_queue[i] = create_arraylist();
        self->start_idx[i] = 0;
        self->num_of_ready_host_flows[i] = 0;
        self->last_to_last_pkt_sent[i] = -1;
        self->last_pkt_sent[i] = -1;
        self->last_to_last_pkt_sent_temp[i] = -1;
        self->last_pkt_sent_temp[i] = -1;
        self->last_to_last_pkt_recvd[i] = -1;
        self->last_pkt_recvd[i] = -1;
        self->host_flows[i] = create_host_flow(node_index, i);
        self->dst_flows[i] = create_dst_flow(i, node_index);
        self->link[i] = create_link(node_index, i, LINK_CAPACITY);
        for (int16_t j = 0; j < NUM_OF_NODES; ++j) {
            self->host_pkt_allocated[i][j] = 0;
            self->fwd_pkt_allocated[i][j] = 0;
            self->last_throttle_value[i][j] = 0;
        }
        self->active_node[i] = 1; // all nodes are created as active
        self->num_of_host_pkt_allocated[i] = 0;
    }

    self->num_of_active_host_flows = 0;
    self->num_of_active_network_host_flows = 0;
    self->curr_num_of_sending_nodes = 0;

    self->stat = (stats_t) {
        .host_pkt_transmitted = 0,
        .non_host_pkt_transmitted = 0,
        .dummy_pkt_transmitted = 0,
        .pkt_received = 0,
        .host_pkt_received = 0,
        .non_host_pkt_received = 0,
        .dummy_pkt_received = 0,
        .total_time_active = 0,
        .flow_stat_list = create_arraylist(),
        .curr_incast_degree = 0,
        .max_incast_degree = 0,
        .max_queuing = 0,
        .current_agg_queue_size = 0
    };

    for (int i = 0; i < NUM_OF_NODES; ++i) {
        self->seq_num[i] = 0;
        self->re_order_buffer[i] = create_arraylist();
        self->curr_seq_num[i] = 0;
    }
    self->max_re_order_buffer_size = 0;

    return self;
}

void free_node(node_t self)
{
    if (self != NULL) {
        for (int16_t i = 0; i < NUM_OF_NODES; ++i) {
            free_bounded_buffer(self->fwd_buffer[i]);
            free_arraylist(self->host_flow_queue[i]);
            free_host_flow(self->host_flows[i]);
            free_dst_flow(self->dst_flows[i]);
            free_link(self->link[i]);
            free_arraylist(self->re_order_buffer[i]);
        }

        free(self);
    }
}
